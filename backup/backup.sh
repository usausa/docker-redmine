#!/bin/bash
# Redmine のバックアップ（DB ＋ 添付ファイル ＋ 構成）
#
# 使い方:
#   ./backup/backup.sh
#   BACKUP_DIR=/mnt/backup ./backup/backup.sh
#
# ⚠️ Redmine 本体やプラグインを更新する直前には必ず1回実行すること。
#    マイグレーションは原則として前方向のみで、イメージを戻しても DB は戻らない。
#
# cron 例（毎日 2:30）:
#   30 2 * * * cd /path/to/docker-redmine && ./backup/backup.sh >> backup/backup.log 2>&1

set -euo pipefail

cd "$(dirname "$0")/.."

TS=$(date +%Y%m%d-%H%M%S)
DEST="${BACKUP_DIR:-./backup/archive}/$TS"
KEEP="${KEEP_GENERATIONS:-7}"

mkdir -p "$DEST"
echo "=== backup start: $TS -> $DEST ==="

# --- データベース ---
echo "--- pg_dump ---"
docker compose exec -T db pg_dump -U redmine -d redmine | gzip > "$DEST/redmine-db.sql.gz"
echo "    $(du -h "$DEST/redmine-db.sql.gz" | cut -f1)"

# --- 添付ファイル ---
echo "--- files ---"
if [ -d ./data/files ]; then
  tar czf "$DEST/files.tar.gz" -C ./data files
  echo "    $(du -h "$DEST/files.tar.gz" | cut -f1)"
else
  echo "    (data/files が無いためスキップ)"
fi

# --- 構成ファイル ---
# .env は実値を含む。保管先の権限に注意すること。
echo "--- config ---"
tar czf "$DEST/config.tar.gz" \
  --exclude='vendor/*.zip' \
  compose.yaml Dockerfile plugins.tsv themes.tsv config patches setup .env.example \
  $( [ -f .env ] && echo .env ) 2>/dev/null || true

# --- 世代管理 ---
BASE="${BACKUP_DIR:-./backup/archive}"
COUNT=$(find "$BASE" -maxdepth 1 -mindepth 1 -type d | wc -l)
if [ "$COUNT" -gt "$KEEP" ]; then
  echo "--- rotate (keep $KEEP of $COUNT) ---"
  find "$BASE" -maxdepth 1 -mindepth 1 -type d | sort | head -n "$((COUNT - KEEP))" | while read -r old; do
    echo "    remove $old"
    rm -rf "$old"
  done
fi

echo "=== backup done: $DEST ==="
echo
echo "リストア手順:"
echo "  docker compose down"
echo "  rm -rf data/postgres && mkdir -p data/postgres"
echo "  docker compose up -d db"
echo "  docker compose ps db    # db が healthy になるまで待つ"
echo "  zcat $DEST/redmine-db.sql.gz | docker compose exec -T db psql -U redmine -d redmine"
echo "  tar xzf $DEST/files.tar.gz -C ./data"
echo "  docker compose up -d"
echo
echo "⚠️ リストアは一度実際に試してから本番運用に入ること。"
