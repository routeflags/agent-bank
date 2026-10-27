#!/usr/bin/env bash
# 本番 MySQL のバックアップを取得する。
#
# 実行場所: VPS 上のリポジトリ直下で `sudo bash script/db_backup.sh`
# 前提: compose.production.yaml（サービス名 mysql、イメージ mysql:8.4、named volume）。
#   mysql サービスの環境変数に MYSQL_ROOT_PASSWORD が定義されていること。
#
# 環境変数:
#   COMPOSE_FILE   Compose ファイル（既定: compose.production.yaml）
#   BACKUP_DIR     出力先（既定: /var/backups/agent-bank/db）
#   KEEP           保持世代数（既定: 14。`KEEP=30 sudo bash script/db_backup.sh` のように変更可）
#   MYSQL_DATABASE ダンプ対象 DB（既定: sharetribe_production）
#   PREFIX         ファイル名接頭辞（既定: 空。db_restore.sh が復元前退避に pre-restore- を指定）
#   DRY_RUN=1      コマンドを表示するだけで実行しない
set -euo pipefail

: "${COMPOSE_FILE:=compose.production.yaml}"
: "${BACKUP_DIR:=/var/backups/agent-bank/db}"
: "${KEEP:=14}"
: "${MYSQL_DATABASE:=sharetribe_production}"
: "${PREFIX:=}"
: "${DRY_RUN:=0}"

cd "$(dirname "$0")/.."

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FINAL_FILE="${BACKUP_DIR}/${PREFIX}${TIMESTAMP}.sql.gz"
# 先頭ドット付きにすることで、保持世代の `*.sql.gz` 展開や一覧に混ざらない。
TMP_FILE="${BACKUP_DIR}/.tmp.${TIMESTAMP}.$$.sql.gz"

# 成功・失敗いずれでも途中ファイルを残さない（成功時は mv 済みのため何もしない）。
cleanup() {
  rm -f "$TMP_FILE" 2>/dev/null || true
}
trap cleanup EXIT

dump_pipeline() {
  docker compose -f "$COMPOSE_FILE" exec -T \
    -e "MYSQL_DATABASE=${MYSQL_DATABASE}" \
    mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --quick --routines "$MYSQL_DATABASE"' \
    | gzip -c >"$TMP_FILE"
}

if [ "$DRY_RUN" = "1" ]; then
  cat <<EOF
+ mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
+ docker compose -f "$COMPOSE_FILE" exec -T -e "MYSQL_DATABASE=${MYSQL_DATABASE}" mysql sh -c 'exec mysqldump -uroot -p"\$MYSQL_ROOT_PASSWORD" --single-transaction --quick --routines "$MYSQL_DATABASE"' | gzip -c > "$TMP_FILE"
+ gzip -t "$TMP_FILE"
+ chmod 600 "$TMP_FILE" && mv "$TMP_FILE" "$FINAL_FILE"
+ find "$BACKUP_DIR" -maxdepth 1 -name '*.sql.gz' を更新順に並べ、${KEEP} 世代を超えた古いものから削除
EOF
  exit 0
fi

command -v docker >/dev/null 2>&1 || {
  echo "error: docker コマンドが見つかりません" >&2
  exit 1
}

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

dump_pipeline

# 転送途中で切れたダンプを正規ファイルにしないための検証。
gzip -t "$TMP_FILE"

chmod 600 "$TMP_FILE"
mv "$TMP_FILE" "$FINAL_FILE"

# 保持世代を超えた古いものから削除（新しい順に KEEP 件残す）。
mapfile -t OLD_FILES < <(find "$BACKUP_DIR" -maxdepth 1 -name '*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n +$((KEEP + 1)) | cut -d' ' -f2- || true)
if [ "${#OLD_FILES[@]}" -gt 0 ]; then
  printf '削除: %s\n' "${OLD_FILES[@]}"
  rm -f -- "${OLD_FILES[@]}"
fi

echo "バックアップ完了: ${FINAL_FILE}"
ls -lh "$FINAL_FILE"
