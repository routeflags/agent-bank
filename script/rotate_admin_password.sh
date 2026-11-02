#!/usr/bin/env bash
# 管理者パスワードのローテーション（Issue #120）。
#
# 使い方（VPS 上で実行）:
#   cd /opt/agent-bank
#   sudo bash script/rotate_admin_password.sh
#   ADMIN_USERNAME=<username> sudo -E bash script/rotate_admin_password.sh
#
# やること:
#   1. ランダムな 32 文字（base64）のパスワードを「一時ファイル」に生成する
#   2. そのファイルを web コンテナへ渡し、rails runner で Person の
#      password / password_confirmation を更新する
#   3. コンテナ内の `.env`（＝ホストの ${REMOTE_DIR}/.env）の
#      ADMIN_PASSWORD を新しい値に差し替える
#
# パスワードはコマンドライン引数・標準出力・シェル履歴に残さない。
# 実行後、オーナーは `.env` から新しい値を確認できる（`sudo` で読む）。
set -euo pipefail

REMOTE_DIR="${REMOTE_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-compose.production.yaml}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin2}"
SERVICE="${SERVICE:-web}"

cd "$REMOTE_DIR"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "error: ${COMPOSE_FILE} が見つかりません（REMOTE_DIR=${REMOTE_DIR}）" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker が見つかりません" >&2
  exit 1
fi

PW_FILE=$(mktemp)
ENV_TMP=$(mktemp)
RUNNER_FILE=$(mktemp)
chmod 600 "$PW_FILE" "$ENV_TMP"
cleanup() { rm -f "$PW_FILE" "$ENV_TMP" "$RUNNER_FILE"; }
trap cleanup EXIT

# 1) パスワード生成（他ユーザーから読めない一時ファイルへ）
umask 077
openssl rand -base64 32 | tr -d '\n' > "$PW_FILE"

# 2) 更新スクリプト（値はファイルから読む。引数には載せない）
cat > "$RUNNER_FILE" <<'RUBY'
pw = File.read("/tmp/new_admin_pw.txt").chomp
username = ENV.fetch("ADMIN_USERNAME")
person = Person.find_by(username: username)
abort("person not found: #{username}") if person.nil?
person.password = pw
person.password_confirmation = pw
abort(person.errors.full_messages.join(", ")) unless person.save
puts "updated=#{person.username}"
RUBY

docker compose -f "$COMPOSE_FILE" cp "$PW_FILE" "${SERVICE}:/tmp/new_admin_pw.txt"
docker compose -f "$COMPOSE_FILE" cp "$RUNNER_FILE" "${SERVICE}:/tmp/rotate_admin_password.rb"
docker compose -f "$COMPOSE_FILE" exec -T -e ADMIN_USERNAME="$ADMIN_USERNAME" \
  "$SERVICE" bin/rails runner /tmp/rotate_admin_password.rb
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" rm -f /tmp/new_admin_pw.txt /tmp/rotate_admin_password.rb

# 3) .env の ADMIN_PASSWORD を差し替える（無ければ追記）
if [ -f .env ]; then
  PW_VALUE=$(cat "$PW_FILE")
  awk -v pw="$PW_VALUE" '
    BEGIN { done = 0 }
    /^ADMIN_PASSWORD=/ { print "ADMIN_PASSWORD=" pw; done = 1; next }
    { print }
    END { if (!done) print "ADMIN_PASSWORD=" pw }
  ' .env > "$ENV_TMP"
  chmod --reference=.env "$ENV_TMP" 2>/dev/null || true
  mv "$ENV_TMP" .env
  echo ".env の ADMIN_PASSWORD を更新しました（値は表示しません）"
else
  echo "warning: ${REMOTE_DIR}/.env が無いため ADMIN_PASSWORD は更新していません" >&2
fi

echo "done: ${ADMIN_USERNAME} のパスワードをローテーションしました"
echo "新しいパスワードは ${REMOTE_DIR}/.env の ADMIN_PASSWORD を参照してください"
