# Redmine の初期設定
#
# 初回の起動のあとに1回実行する。
#   docker compose exec -u redmine redmine bin/rails runner setup/initial_setup.rb
#
# 管理画面で行う設定を、Redmine の機能（モデルと設定）を通して登録する。Redmine 本体とプラグインのソースは変えない。
# 何度実行しても同じ結果になる。ただし次の点に注意する。
#   - ステータス・トラッカー・カスタムフィールド・表示のカスタマイズは、すでにあれば変えない
#   - 管理 > 設定 の項目は、このスクリプトの値に戻る
#
# 環境ごとの値は .env から環境変数で受け取る（compose.yaml が渡す）。
#   SETUP_HOST_NAME    利用者が開く URL のホスト名とポート（通知メールのリンクに使う）
#   SETUP_PROTOCOL     http または https
#   SETUP_MAIL_FROM    通知メールの送信元アドレス
#   SETUP_ADMIN_EMAIL  admin のメールアドレス

require 'yaml'

SETUP_DIR = __dir__

# 通知メールの送信待ちなどのログで結果が読みにくくならないようにする
Rails.logger.level = Logger::WARN

def section(title)
  puts "== #{title}"
end

def note(message)
  puts "   #{message}"
end

def env_value(name)
  ENV[name].to_s.strip.presence
end

def normalize(value)
  value.is_a?(Array) ? value.map(&:to_s) : value.to_s
end

warnings = []

admin = User.find_by(login: 'admin') || User.where(admin: true).order(:id).first
abort '管理者のユーザーが見つからない' unless admin
User.current = admin

# ---------------------------------------------------------------------------
section '既定データ（日本語）'
if Redmine::DefaultData::Loader.no_data?
  Redmine::DefaultData::Loader.load('ja')
  note '読み込んだ'
else
  note 'すでにある（読み込まない）'
end

# ---------------------------------------------------------------------------
# ステータスは既定データを改名して ID 1〜6 を保ち、🚫阻害 を最後に足して ID 7 にする。
# setup/view_customize/01_issue-list-status-colors.css が、この ID で色を付ける。
section 'チケットのステータス'
[
  ['新規', '🆕新規', false],
  ['進行中', '🚧進行中', false],
  ['解決', '✅解決', false],
  ['フィードバック', '❌差戻', false],
  ['終了', '🚀終了', true],
  ['却下', '💔却下', true]
].each do |default_name, name, closed|
  status = IssueStatus.find_by(name: name) || IssueStatus.find_by(name: default_name)
  if status
    status.update!(name: name, is_closed: closed)
  else
    warnings << "ステータス「#{default_name}」が無いため、「#{name}」を作れなかった"
  end
end
in_progress = IssueStatus.find_by(name: '🚧進行中')
blocked = IssueStatus.find_by(name: '🚫阻害') || IssueStatus.create!(name: '🚫阻害', is_closed: false)
if in_progress && blocked.reload.position != in_progress.reload.position + 1
  blocked.update!(position: in_progress.position + 1)
end
note IssueStatus.sorted.map { |s| "#{s.id}:#{s.name}" }.join(' ')
{ '🆕新規' => 1, '🚧進行中' => 2, '✅解決' => 3, '❌差戻' => 4, '🚀終了' => 5, '💔却下' => 6, '🚫阻害' => 7 }.each do |name, id|
  actual = IssueStatus.find_by(name: name)&.id
  next if actual == id

  warnings << "ステータス「#{name}」の ID が #{actual.inspect}（#{id} のはず）。" \
              'setup/view_customize/01_issue-list-status-colors.css の status-N を合わせること'
end

# ---------------------------------------------------------------------------
section 'トラッカー'
new_status = IssueStatus.find_by(name: '🆕新規')
trackers = [
  ['機能', '✨機能', true],
  ['バグ', '🐛バグ', false],
  ['サポート', '🤝サポート', false],
  [nil, '👀レビュー', true],
  [nil, '🎫課題', true]
].map do |default_name, name, roadmap|
  tracker = Tracker.find_by(name: name) || (default_name && Tracker.find_by(name: default_name)) || Tracker.new
  tracker.name = name
  tracker.is_in_roadmap = roadmap
  tracker.default_status = new_status
  tracker.save! if tracker.new_record? || tracker.changed?
  tracker
end
trackers.each_with_index do |tracker, index|
  tracker.reload
  tracker.update!(position: index + 1) unless tracker.position == index + 1
end
feature, bug, support, review, task = trackers
note Tracker.sorted.map { |t| "#{t.id}:#{t.name}" }.join(' ')

# ---------------------------------------------------------------------------
section 'チケットの優先度'
[['低め', '🔽低め'], ['高め', '🔺高め'], ['急いで', '⏰急いで'], ['今すぐ', '🆘今すぐ']].each do |default_name, name|
  priority = IssuePriority.find_by(name: name) || IssuePriority.find_by(name: default_name)
  if priority
    priority.update!(name: name)
  else
    warnings << "優先度「#{default_name}」が無いため、「#{name}」にできなかった"
  end
end
note IssuePriority.sorted.map { |p| "#{p.id}:#{p.name}#{p.is_default ? '（既定）' : ''}" }.join(' ')

# ---------------------------------------------------------------------------
# ロールは既定データの 管理者・開発者・報告者 を使い、プラグインの権限を足す（管理者は既定ですべての権限を持つ）。
section 'ロールの権限'
manager = Role.find_by(name: '管理者')
developer = Role.find_by(name: '開発者')
reporter = Role.find_by(name: '報告者')
[
  [developer, %i[view_checklists done_checklists edit_checklists show_issue_templates edit_issue_templates
                 manage_issue_templates manage_banner add_wiki_comment]],
  [reporter, %i[view_checklists show_issue_templates]]
].each do |role, permissions|
  next warnings << 'ロール「開発者」または「報告者」が無いため、権限を足せなかった' unless role

  missing = permissions - role.permissions
  role.add_permission!(*missing) if missing.any?
  note "#{role.name}: #{missing.any? ? "#{missing.join(' ')} を足した" : '変更なし'}"
end

# ---------------------------------------------------------------------------
# 既定データのワークフローに 🚫阻害 との行き来を足し、👀レビュー と 🎫課題 には ✨機能 のワークフローを写す。
section 'ワークフロー'
if manager && developer && in_progress
  add_transition = lambda do |tracker, role, from, to|
    WorkflowTransition.find_or_create_by!(tracker_id: tracker.id, role_id: role.id,
                                          old_status_id: from.id, new_status_id: to.id,
                                          author: false, assignee: false)
  end
  others = IssueStatus.where.not(id: blocked.id).to_a
  [feature, bug, support].each do |tracker|
    others.each do |status|
      add_transition.call(tracker, manager, status, blocked)
      add_transition.call(tracker, manager, blocked, status)
    end
    add_transition.call(tracker, developer, in_progress, blocked)
    add_transition.call(tracker, developer, blocked, in_progress)
  end
  [review, task].each do |tracker|
    if WorkflowTransition.where(tracker_id: tracker.id).exists?
      note "#{tracker.name}: すでにある（写さない）"
    else
      WorkflowRule.copy(feature, nil, [tracker], Role.all.select(&:consider_workflow?))
      note "#{tracker.name}: #{feature.name} のワークフローを写した"
    end
  end
  note Tracker.sorted.map { |t| "#{t.name}=#{WorkflowTransition.where(tracker_id: t.id).count}" }.join(' ')
else
  warnings << 'ロールまたはステータスが足りないため、ワークフローを設定できなかった'
end

# ---------------------------------------------------------------------------
section 'カスタムフィールド'
definitions = YAML.safe_load(File.read(File.join(SETUP_DIR, 'custom_fields.yml'))) || {}
local_path = File.join(SETUP_DIR, 'custom_fields.local.yml')
if File.exist?(local_path)
  local = YAML.safe_load(File.read(local_path)) || {}
  %w[project issue].each do |kind|
    Array(local[kind]).each do |item|
      base = (definitions[kind] ||= []).find { |d| d['name'] == item['name'] }
      base ? base.merge!(item) : definitions[kind] << item
    end
  end
  note 'custom_fields.local.yml も読んだ'
end
Array(definitions['project']).each do |d|
  if ProjectCustomField.exists?(name: d['name'])
    note "#{d['name']}: すでにある"
  else
    ProjectCustomField.create!(name: d['name'], field_format: d.fetch('format', 'string'), visible: d.fetch('visible', true))
    note "#{d['name']}: 作った"
  end
end
Array(definitions['issue']).each do |d|
  if IssueCustomField.exists?(name: d['name'])
    note "#{d['name']}: すでにある"
  else
    IssueCustomField.create!(name: d['name'], field_format: d.fetch('format', 'list'), possible_values: Array(d['values']),
                             is_filter: d.fetch('filter', false), searchable: d.fetch('searchable', false),
                             is_for_all: true, visible: true, tracker_ids: Tracker.pluck(:id))
    note "#{d['name']}: 作った（選択肢 #{Array(d['values']).size} 件）"
  end
end

# ---------------------------------------------------------------------------
section '管理 > 設定'
values = {
  'app_title' => '課題管理',
  'activity_days_default' => '30',
  'default_language' => 'ja',
  'user_format' => 'lastname_firstname',
  'ui_theme' => 'farend_fancy',
  'start_of_week' => '1',
  'date_format' => '%Y-%m-%d',
  'time_format' => '%H:%M',
  'timespan_format' => 'decimal',
  'per_page_options' => '50,100',
  'self_registration' => '0',
  'autologin' => '30',
  'session_lifetime' => '43200',
  'session_timeout' => '1440',
  'rest_api_enabled' => '1',
  'jsonp_enabled' => '1',
  'default_projects_modules' => %w[issue_tracking wiki repository calendar gantt banner issue_templates wiki_extensions issues_panel],
  'default_projects_tracker_ids' => [bug, feature, support, review].map { |t| t.id.to_s },
  'display_subprojects_issues' => '0',
  'default_issue_start_date_to_creation_date' => '1',
  'issue_list_default_columns' => %w[tracker status priority subject author assigned_to start_date updated_on due_date done_ratio],
  'issue_done_ratio' => 'issue_field',
  'plain_text_mail' => '1',
  'default_notification_option' => 'only_my_events',
  'enabled_scm' => %w[Subversion Mercurial Git]
}
protocol = env_value('SETUP_PROTOCOL') || 'http'
values['protocol'] = protocol
if (host = env_value('SETUP_HOST_NAME'))
  values['host_name'] = host
  values['emails_footer'] = Setting.emails_footer.to_s.gsub(%r{https?://\S+/my/account}, "#{protocol}://#{host}/my/account")
else
  warnings << 'SETUP_HOST_NAME が空のため、「ホスト名とパス」を設定しなかった（通知メールのリンクが localhost:3000 のままになる）'
end
if (mail_from = env_value('SETUP_MAIL_FROM'))
  values['mail_from'] = mail_from
else
  warnings << 'SETUP_MAIL_FROM が空のため、「送信元メールアドレス」を設定しなかった'
end
changed = values.reject { |name, value| normalize(Setting.send(name)) == normalize(value) }
changed.each { |name, value| Setting.send("#{name}=", value) }
note changed.any? ? "変えた項目: #{changed.keys.join(', ')}" : '変更なし'

# ---------------------------------------------------------------------------
section 'プラグインの設定'
{
  'redmine_checklists' => { 'issue_done_ratio' => '1', 'block_issue_closing' => '1' },
  'redmine_issue_assign_notice' => { 'notice_url_each_project' => '1' }
}.each do |plugin, wanted|
  current = (Setting.send("plugin_#{plugin}") || {}).to_h.stringify_keys
  merged = current.merge(wanted)
  if merged == current
    note "#{plugin}: 変更なし"
  else
    Setting.send("plugin_#{plugin}=", merged)
    note "#{plugin}: #{wanted.keys.join(', ')} を設定した"
  end
end

# ---------------------------------------------------------------------------
# コメントの先頭をファイル名にして、登録済みかどうかを見分ける。
section '表示のカスタマイズ（view_customize）'
[
  ['01_issue-list-status-colors.css', '/projects/.*/issues', 'css',
   'チケット一覧: 期日超過とステータスごとの色、作成者・担当者の列の省略表示'],
  ['02_issue-list-noupdate60.js', '/projects/.*/issues', 'javascript',
   'チケット一覧: 60日以上更新の無い行に noupdate60 を付ける（01 の CSS と組み合わせる）'],
  ['03_attachment-lightbox.js', '', 'javascript',
   '添付画像のサムネイルを、ページを移らずに拡大表示する'],
  ['04_plugin-icon-fix.css', '', 'css',
   'プラグイン（redmine_banner・redmine_issue_templates）のアイコンが文字に重なるのを直す']
].each do |file, path_pattern, type, description|
  if ViewCustomize.all.any? { |v| v.comments.to_s.start_with?("#{file}:") }
    note "#{file}: すでにある"
    next
  end

  ViewCustomize.create!(path_pattern: path_pattern, project_pattern: '', customize_type: type,
                        code: File.read(File.join(SETUP_DIR, 'view_customize', file)),
                        insertion_position: 'html_head', is_enabled: true, is_private: false,
                        comments: "#{file}: #{description}", author_id: admin.id)
  note "#{file}: 登録した"
end

# ---------------------------------------------------------------------------
# 全員に公開する保存済みクエリ。同じ名前のクエリがあれば変えない。
section '保存済みクエリ'
status_id = ->(name) { IssueStatus.find_by(name: name)&.id&.to_s }
[
  # [名前, 絞り込み, まとめ方, 並び順, 足す列]
  ['🍺 進行中', [['status_id', '=', [status_id.call('🚧進行中')]]], 'assigned_to', [%w[assigned_to asc], %w[due_date asc]]],
  ['⚡ 期日1週間前', [['status_id', 'o', []], ['due_date', '><t+', ['7']]], nil, [%w[due_date asc]]],
  ['🍜 100日経過', [['status_id', 'o', []], ['updated_on', '<t-', ['100']]], nil, [%w[updated_on asc]]],
  ['🍣 直近7日間の変更', [['status_id', '*', []], ['updated_on', '><t-', ['7']]], 'assigned_to', [%w[updated_on desc]],
   %w[last_updated_by]],
  ['🍉 作業未着手', [['status_id', '=', [status_id.call('🆕新規')]]], 'assigned_to', [%w[start_date asc], %w[id asc]]],
  ['🧑 自担当作業', [['status_id', 'o', []], ['assigned_to_id', '=', ['me']]], nil, [%w[priority desc], %w[due_date asc]]],
  ['⏲️ 更新の新しい順', [['status_id', '*', []]], nil, [%w[updated_on desc]]]
].each do |name, filters, group_by, sort, extra_columns|
  if IssueQuery.where(project_id: nil, name: name).exists?
    note "#{name}: すでにある"
    next
  end
  if filters.any? { |_, _, values| values.include?(nil) }
    warnings << "保存済みクエリ「#{name}」の条件に使うステータスが無いため、作れなかった"
    next
  end

  query = IssueQuery.new(name: name, user: admin, visibility: IssueQuery::VISIBILITY_PUBLIC)
  query.filters = {}
  filters.each { |field, operator, values| query.add_filter(field, operator, values) }
  query.group_by = group_by
  query.sort_criteria = sort
  query.column_names = Setting.issue_list_default_columns + extra_columns if extra_columns
  query.save!
  note "#{name}: 作った"
end

# ---------------------------------------------------------------------------
section 'admin のメールアドレス'
if (email = env_value('SETUP_ADMIN_EMAIL'))
  if admin.mail == email
    note '変更なし'
  else
    admin.update!(mail: email)
    note '設定した'
  end
else
  warnings << 'SETUP_ADMIN_EMAIL が空のため、admin のメールアドレスを設定しなかった'
end

puts
if warnings.empty?
  puts '✅ 初期設定が終わった'
else
  puts '⚠️ 確認が必要なこと'
  warnings.each { |w| puts "   - #{w}" }
end
