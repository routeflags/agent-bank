#!/usr/bin/env bash
# 管理者のパスワードを推測困難な値にローテーションする（Issue #120）。
#
# 使い方（VPS のリポジトリ直下で）:
#   sudo bash script/rotate_admin_password.sh
#   ADMIN_USERNAME=alexm sudo -E bash script/rotate_admin_password.sh
#
# 動作:
#   1. 英数字 32 文字のランダムなパスワードを生成
#   2. 一時ファイル経由でコンテナへ渡し、`rails runner` で該当 person を更新
#      （コマンドライン引数・標準出力にパスワードを出さない）
#   3. `.env` の `ADMIN_PASSWORD` を新しい値に更新（rsync の対象外）
#   4. 新しいパスワード自体は表示しない。取得方法だけを案内する
#
# 前提: `compose.production.yaml` の web サービスが起動していること。
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-compose.production.yaml}"
ADMIN_USERNAME="${ADMIN_USERNAME:-alexm}"
ENV_FILE="${ENV_FILE:-.env}"

cd "$(dirname "$0")/.."

[ -f "$ENV_FILE" ] || { echo "error: ${ENV_FILE} が見つかりません" >&2; exit 1; }

generate_password() {
  local pw
  while :; do
    pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
    # 大文字・小文字・数字をすべて含むものだけ採用する。
    if [[ "$pw" == *[A-Z]* && "$pw" == *[a-z]* && "$pw" == *[0-9]* ]]; then
      printf '%s' "$pw"
      return 0
    fi
  done
}

umask 077
TMP_PW="$(mktemp)"
TMP_RB="$(mktemp)"
cleanup() { rm -f "$TMP_PW" "$TMP_RB"; }
trap cleanup EXIT

generate_password >"$TMP_PW"

cat >"$TMP_RB" <<'RUBY'
pw = File.read("/tmp/rotate_admin_password.txt").chomp
username = ENV.fetch("ADMIN_USERNAME")
person = Person.find_by(username: username)
abort("person not found: #{username}") if person.nil?
person.password = pw
person.password_confirmation = pw
abort("update failed: #{person.errors.full_messages.join(', ')}") unless person.save
puts "updated=#{person.username}"
RUBY

# `docker compose cp` はコピー元のパーミッションを引き継ぐため、コンテナ内の
# 実行ユーザー（app）が読めるように 0644 にしてからコピーする。直後に削除する。
chmod 0644 "$TMP_PW" "$TMP_RB"

docker compose -f "$COMPOSE_FILE" cp "$TMP_PW" web:/tmp/rotate_admin_password.txt >/dev/null
docker compose -f "$COMPOSE_FILE" cp "$TMP_RB" web:/tmp/rotate_admin_password.rb >/dev/null

docker compose -f "$COMPOSE_FILE" exec -T -e ADMIN_USERNAME="$ADMIN_USERNAME" \
  web bundle exec rails runner /tmp/rotate_admin_password.rb

# コンテナ内の一時ファイルは root 所有なので、root で消す。
docker compose -f "$COMPOSE_FILE" exec -T -u root web \
  rm -f /tmp/rotate_admin_password.txt /tmp/rotate_admin_password.rb

ADMIN_PASSWORD_FILE="$TMP_PW" python3 - "$ENV_FILE" <<'PY'
import os, sys
env_path = sys.argv[1]
new_pw = open(os.environ["ADMIN_PASSWORD_FILE"]).read().strip()
lines = [l.rstrip("\n") for l in open(env_path) if l.strip() and not l.startswith("#")]
kv = [(l.split("=", 1)[0], l.split("=", 1)[1]) for l in lines]
d = dict(kv)
order = [k for k, _ in kv]
d["ADMIN_PASSWORD"] = new_pw
if "ADMIN_PASSWORD" not in order:
    order.append("ADMIN_PASSWORD")
open(env_path, "w").write("".join("%s=%s\n" % (k, d[k]) for k in order))
print("env_updated=ADMIN_PASSWORD")
PY

echo "ローテーション完了（パスワードは表示しません）。"
echo "確認: grep '^ADMIN_PASSWORD=' ${ENV_FILE}"
