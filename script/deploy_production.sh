#!/usr/bin/env bash
# VPS（さくらのVPS）へ本番デプロイする（Issue #99）。
#
# やること:
#   1. 作業ツリーを VPS の REMOTE_DIR へ rsync（.env とビルド成果物は除外）
#   2. VPS 上で `docker compose build web` → `up -d`
#   3. web の healthcheck が通るまで待つ
#   4. コンテナ内から script/smoke_check.rb を実行して回帰確認
#
# 使い方（ローカルのリポジトリ直下で実行）:
#   bash script/deploy_production.sh
#   HOST=ubuntu@1.2.3.4 bash script/deploy_production.sh
#   SKIP_SMOKE=1 bash script/deploy_production.sh     # スモークを省略
#
# 前提:
# - VPS の `~/.env` に `ROOT_PASSWORD`（sudo 用）があること。
# - VPS の `${REMOTE_DIR}/.env` は rsync で上書きしない（秘密情報の置き場）。
# - 秘密情報は一切表示しない。コマンドは VPS 側で組み立て、パスワードは
#   `sudo -S` に標準入力で渡す。
set -euo pipefail

HOST="${HOST:-ubuntu@153.126.189.79}"
REMOTE_DIR="${REMOTE_DIR:-/opt/agent-bank}"
COMPOSE_FILE="${COMPOSE_FILE:-compose.production.yaml}"
SKIP_SMOKE="${SKIP_SMOKE:-0}"

cd "$(dirname "$0")/.."

echo "==> 1/4 rsync: $(pwd) -> ${HOST}:${REMOTE_DIR}"
rsync -az --delete \
  --exclude '.git' \
  --exclude '.delta' \
  --exclude '.env' \
  --exclude 'node_modules' \
  --exclude 'client/node_modules' \
  --exclude 'vendor/bundle' \
  --exclude 'tmp' \
  --exclude 'log' \
  --exclude 'public/assets' \
  --exclude 'public/webpack' \
  --exclude 'public/packs' \
  --exclude '.rspec_status' \
  ./ "${HOST}:${REMOTE_DIR}/"

echo "==> 2/4 build + up（VPS 上）"
ssh -o BatchMode=yes "$HOST" "REMOTE_DIR='${REMOTE_DIR}' COMPOSE_FILE='${COMPOSE_FILE}' bash -s" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_DIR"
PW=$(sed -n 's/^ROOT_PASSWORD=//p' ~/.env | head -1)
S() { echo "$PW" | sudo -S -p "" "$@"; }

S docker compose -f "$COMPOSE_FILE" build web
S docker compose -f "$COMPOSE_FILE" up -d
REMOTE

echo "==> 3/4 healthcheck 待ち"
ssh -o BatchMode=yes "$HOST" "REMOTE_DIR='${REMOTE_DIR}' COMPOSE_FILE='${COMPOSE_FILE}' bash -s" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_DIR"
PW=$(sed -n 's/^ROOT_PASSWORD=//p' ~/.env | head -1)
S() { echo "$PW" | sudo -S -p "" "$@"; }

for i in $(seq 1 60); do
  status=$(S docker compose -f "$COMPOSE_FILE" ps --format '{{.Service}} {{.Health}}' 2>/dev/null | grep '^web ' || true)
  case "$status" in
    "web healthy") echo "web: healthy"; exit 0 ;;
  esac
  sleep 10
done
echo "error: web が healthy になりません（最後の状態: ${status:-unknown}）" >&2
S docker compose -f "$COMPOSE_FILE" logs --tail=40 web >&2 || true
exit 1
REMOTE

if [ "$SKIP_SMOKE" = "1" ]; then
  echo "==> 4/4 スモーク: 省略（SKIP_SMOKE=1）"
  exit 0
fi

echo "==> 4/4 スモーク（コンテナ内から）"
ssh -o BatchMode=yes "$HOST" "REMOTE_DIR='${REMOTE_DIR}' COMPOSE_FILE='${COMPOSE_FILE}' bash -s" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_DIR"
PW=$(sed -n 's/^ROOT_PASSWORD=//p' ~/.env | head -1)
S() { echo "$PW" | sudo -S -p "" "$@"; }

# 公開ホスト名は .env の APP_DOMAIN（Caddy のサイトアドレス）に合わせる。
APP_DOMAIN=$(sed -n 's/^APP_DOMAIN=//p' .env | head -1)
BASE="http://${APP_DOMAIN:-localhost}"

echo "smoke base: $BASE"
S docker run --rm --network host \
  -v "${REMOTE_DIR}/script/smoke_check.rb:/tmp/smoke_check.rb:ro" \
  agent-bank-web ruby /tmp/smoke_check.rb "$BASE"
REMOTE

echo "==> デプロイ完了"
