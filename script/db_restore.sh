#!/usr/bin/env bash
# バックアップファイルから本番 MySQL を復元する。
#
# 使い方: sudo bash script/db_restore.sh /var/backups/agent-bank/db/20261028-030000.sql.gz [--yes]
#   --yes / -y を付けると確認プロンプトを省略する（cron 等の非対話実行用。手動実行では付けないこと）。
#
# 復元前に現行 DB を別名（pre-restore-*.sql.gz）でダンプしてから復元する。
# 復元後はテーブル数と代表テーブルの行数を表示して検証する。
#
# 環境変数: COMPOSE_FILE / BACKUP_DIR / MYSQL_DATABASE / DRY_RUN=1 は db_backup.sh と同じ。
set -euo pipefail

: "${COMPOSE_FILE:=compose.production.yaml}"
: "${BACKUP_DIR:=/var/backups/agent-bank/db}"
: "${MYSQL_DATABASE:=sharetribe_production}"
: "${DRY_RUN:=0}"

cd "$(dirname "$0")/.."

BACKUP_FILE=""
YES="0"
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES="1" ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    -*) echo "error: 不明なオプション: ${arg}" >&2; exit 2 ;;
    *)
      if [ -n "$BACKUP_FILE" ]; then
        echo "error: バックアップファイルは1件のみ指定できます" >&2
        exit 2
      fi
      BACKUP_FILE="$arg"
      ;;
  esac
done

if [ -z "$BACKUP_FILE" ]; then
  echo "使い方: sudo bash script/db_restore.sh <バックアップファイル> [--yes]" >&2
  exit 2
fi

if [ "$DRY_RUN" != "1" ] && [ ! -f "$BACKUP_FILE" ]; then
  echo "error: ファイルが見つかりません: ${BACKUP_FILE}" >&2
  exit 1
fi

# クエリ実行ヘルパー。第1引数の SQL を mysql サービス上で実行し、結果を標準出力に出す。
# 認証情報はコンテナ側の環境変数（MYSQL_ROOT_PASSWORD）を使い、ホスト側に出さない。
mysql_query() {
  docker compose -f "$COMPOSE_FILE" exec -T \
    -e "MYSQL_DATABASE=${MYSQL_DATABASE}" \
    mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B "$MYSQL_DATABASE" -e "$0"' "$1"
}

restore_pipeline() {
  case "$BACKUP_FILE" in
    *.gz) gzip -dc "$BACKUP_FILE" ;;
    *) cat "$BACKUP_FILE" ;;
  esac | docker compose -f "$COMPOSE_FILE" exec -T \
    -e "MYSQL_DATABASE=${MYSQL_DATABASE}" \
    mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
}

if [ "$DRY_RUN" = "1" ]; then
  cat <<EOF
+ PREFIX="pre-restore-" bash script/db_backup.sh  # 現行 DB の退避（DRY_RUN 継承）
+ gzip -dc "$BACKUP_FILE" | docker compose -f "$COMPOSE_FILE" exec -T -e "MYSQL_DATABASE=${MYSQL_DATABASE}" mysql sh -c 'exec mysql -uroot -p"\$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
+ テーブル数: SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
+ 行数検証: listings / chat_sessions / wallets の SELECT COUNT(*)
EOF
  PREFIX="pre-restore-" bash script/db_backup.sh
  exit 0
fi

command -v docker >/dev/null 2>&1 || {
  echo "error: docker コマンドが見つかりません" >&2
  exit 1
}

if [ "$YES" != "1" ]; then
  cat >&2 <<EOF
復元対象 DB: ${MYSQL_DATABASE}（Compose: ${COMPOSE_FILE}）
復元元: ${BACKUP_FILE}
現行 DB は上書きされます。復元前に現行 DB を ${BACKUP_DIR}/pre-restore-<日時>.sql.gz に退避します。
EOF
  read -r -p "復元しますか？ [y/N]: " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "中止しました。" >&2; exit 1 ;;
  esac
fi

# 1. 現行 DB の退避（失敗したら復元に進まない）。
echo "現行 DB を退避します..."
PREFIX="pre-restore-" bash script/db_backup.sh

# 2. 復元。
echo "復元します: ${BACKUP_FILE} -> ${MYSQL_DATABASE}"
restore_pipeline

# 3. 検証。テーブルごとに成否を記録し、最後にまとめて判定する。
echo "検証します..."
TABLE_COUNT="$(mysql_query 'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()')"
echo "テーブル数: ${TABLE_COUNT}"

FAILED=""
for table in listings chat_sessions wallets; do
  if count="$(mysql_query "SELECT COUNT(*) FROM ${table}" 2>/dev/null)"; then
    echo "${table}: ${count} 行"
  else
    echo "${table}: 取得失敗" >&2
    FAILED="${FAILED} ${table}"
  fi
done

if [ -n "$FAILED" ]; then
  echo "error: 検証に失敗したテーブルがあります:${FAILED}" >&2
  exit 1
fi
echo "復元完了: ${BACKUP_FILE}"
