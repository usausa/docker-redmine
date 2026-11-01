# Redmine 7系 + プラグイン/テーマを「ビルド時に」焼き込むイメージ
#
# 設計の要点:
#   公式イメージの docker-entrypoint.sh は gosu で非特権ユーザー redmine に降格してから
#   `bundle check || bundle install` を実行する。最終イメージではビルドツールが purge
#   されているため、ネイティブ拡張を持つ gem を起動時に導入できない。
#   そこでプラグインの取得と bundle install をビルド時に済ませる。
#   → ビルドが通れば起動は必ず成功する。落ちるならビルド時に落ちる。

ARG REDMINE_VERSION=7.0.2
FROM redmine:${REDMINE_VERSION}-bookworm

USER root
WORKDIR /usr/src/redmine

# 追加するのはビルド依存のみ。
# 公式イメージは git / imagemagick / mercurial / subversion / openssh-client / gsfonts を
# すでに同梱しているため入れ直さない。
#   patch, unzip                                : パッチ適用と zip 配布プラグインの展開
#   build-essential, libpq-dev, libmagickwand-dev: ネイティブ拡張を持つ gem のコンパイル
#   fonts-ipaexfont-gothic                      : ガントの PNG 出力で日本語を描くためのフォント
#                                                 （configuration.yml の minimagick_font_path で指定）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        patch \
        unzip \
        build-essential \
        libpq-dev \
        libmagickwand-dev \
        fonts-ipaexfont-gothic; \
    rm -rf /var/lib/apt/lists/*

COPY plugins.tsv themes.tsv /tmp/
COPY patches/ /tmp/patches/

# --- git 配布のプラグイン ---
# `|| [ -n "$name" ]` は最終行に改行が無い場合も取りこぼさないための保険。
# RUN は /bin/sh（Debian では dash）で動き、bash の $'\t' 記法が使えない。
# そのため printf で TAB を作って IFS に渡す。
RUN set -eux; \
    tab="$(printf '\t')"; \
    while IFS="$tab " read -r name repo ref rest || [ -n "$name" ]; do \
      case "$name" in ''|'#'*) continue ;; esac; \
      echo ">>> plugin: $name @ $ref"; \
      git clone --filter=blob:none "$repo" "plugins/$name"; \
      git -C "plugins/$name" checkout --detach "$ref"; \
      rm -rf "plugins/$name/.git"; \
      if [ -f "/tmp/patches/$name.patch" ]; then \
        echo ">>> patch: $name"; \
        patch -p1 -d "plugins/$name" < "/tmp/patches/$name.patch"; \
      fi; \
    done < /tmp/plugins.tsv

# --- zip 配布のプラグイン（RedmineUP Checklists）---
# vendor/ が空でもビルドは成功する。
COPY vendor/ /tmp/vendor/
RUN set -eux; \
    for z in /tmp/vendor/*.zip; do \
      [ -e "$z" ] || continue; \
      echo ">>> vendor zip: $z"; \
      unzip -q "$z" -d plugins/; \
    done; \
    rm -rf /tmp/vendor

# --- テーマ（Redmine 6.0 以降は themes/。public/themes/ ではない）---
# IFS の作り方はプラグインのループと同じ（dash 対策）。
RUN set -eux; \
    tab="$(printf '\t')"; \
    while IFS="$tab " read -r name repo ref rest || [ -n "$name" ]; do \
      case "$name" in ''|'#'*) continue ;; esac; \
      echo ">>> theme: $name @ $ref"; \
      git clone --filter=blob:none "$repo" "themes/$name"; \
      git -C "themes/$name" checkout --detach "$ref"; \
      rm -rf "themes/$name/.git"; \
    done < /tmp/themes.tsv

# --- gem をビルド時に解決（本方式の核心）---
# 公式イメージと同じ要領（gosu redmine で実行）。
# 公式イメージ側で `bundle config --local without 'development test'` が済んでいる。
RUN set -eux; \
    chown -R redmine:redmine plugins themes; \
    gosu redmine bundle install --jobs "$(nproc)"; \
    rm -f /tmp/plugins.tsv /tmp/themes.tsv; \
    rm -rf /tmp/patches

# 以降は公式イメージの ENTRYPOINT / CMD をそのまま使う
# （ENTRYPOINT ["/docker-entrypoint.sh"] / CMD ["rails","server","-b","0.0.0.0"] / EXPOSE 3000）
