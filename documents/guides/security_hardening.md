# セキュリティ強化の運用ガイド（Issue #120）

公開（80/443 の開放）前に必要なセキュリティ設定のうち、**コードで実装した部分**の
有効化手順と確認方法をまとめる。対象は次の 3 点。

| 項目 | 実装 | 設定キー |
|---|---|---|
| 管理画面（`/ja/admin`）の IP 制限 | `Admin2::AdminBaseController` の `prepend_before_action` | `ADMIN_ALLOWED_IPS` |
| 管理画面向けレート制限 | `config/initializers/rack_attack.rb` の `admin/ip` | （コード側で固定: 60req/5min per IP） |
| TLS 強制とセッション Cookie の `secure` | `config/environments/production.rb` + `config/initializers/session_store.rb` | `FORCE_SSL`（または `APP_DOMAIN` に `https://`） |

> 管理者パスワードのローテーション（オーナー承認が必要な操作）は本ドキュメントの
> 「4. 管理者パスワードのローテーション」に手順のみを記載している。パスワードの値は
> リポジトリ・Issue・チャットのどこにも書かない。

---

## 1. 管理画面（`/ja/admin`）の IP 制限

### 仕組み

- `ADMIN_ALLOWED_IPS` が **空・未設定なら何もしない**（開発・テストの挙動は従来どおり）。
- 設定されているときは、`request.remote_ip` がリストのいずれかに一致しなければ
  **403 Forbidden** を返す（未ログインでもログイン画面へはリダイレクトしない）。
- 判定は `IPAddr` による CIDR マッチ。`/24` などの CIDR、単一 IP、IPv6 を受け付ける。
  複数指定はカンマ区切り。
- 設定値が **一つも解釈できない** 場合は全 IP 拒否（403）に倒す。設定ミスで保護が
  無効になるより安全側に振るためで、その場合はログに警告が出る。

### 有効化手順

1. VPS の `/opt/agent-bank/.env` に許可元を書く（**例**: 自宅 IP と社用 IP）。

   ```dotenv
   # 自宅回線 / 社用回線 / ローカルからの動作確認（IPv6 の ::1 も書ける）
   ADMIN_ALLOWED_IPS=203.0.113.10,198.51.100.0/24,::1
   ```

   全許可にしたい場合（一時的な切り分け用）は `0.0.0.0/0`（IPv4）や `::/0`（IPv6）。

2. web サービスを再起動して `.env` を読み直させる。

   ```bash
   cd /opt/agent-bank
   docker compose -f compose.production.yaml up -d web
   ```

3. 現在の接続元 IP を確認しておく（自宅・社用の回線が変わる場合は再設定が必要）。

   ```bash
   curl -s https://ifconfig.me ; echo   # 自分のグローバル IP（外向き）
   ```

### 確認方法

```bash
# 許可 IP から: 未ログインなら 302（ログイン画面へ）、302 の中身は /ja/login
curl -s -o /dev/null -w "%{http_code}\n" http://<サーバー>/ja/admin

# 許可外 IP から（別回線・モバイル回線など）: 403
curl -s -o /dev/null -w "%{http_code}\n" http://<サーバー>/ja/admin

# ログに拒否理由が出る（IP は記録されるがリクエスト内容は記録しない）
docker compose -f compose.production.yaml logs --tail=50 web | grep AdminAccessControl
```

期待結果: 許可 IP は `302`、許可外 IP は `403`、一般画面（`/ja`）は影響を受けない。

### 注意点

- **`remote_ip` の解決**は `APP_CONFIG.trusted_proxies`（未設定なら Rails 既定の
  private/loopback）に依存する。Caddy が同じ Docker ネットワーク上で
  `X-Forwarded-For` を付ける構成なら、クライアント IP がそのまま入る。
  設定後に思った IP で判定されているかは、拒否ログの `remote_ip=` で確認する。
- このリポジトリの Caddy は外部からの到達を前提にした設定（`Caddyfile`）だが、
  IP 制限は Rails 側で行うため **Caddyfile の変更は不要**。
- 管理画面の**ログイン自体**は従来どおり「管理者（admin）でログイン」が必須。
  IP 制限はその手前の追加防御であり、Basic 認証は導入していない（オーナー判断）。

---

## 2. レート制限（rack-attack）の実効確認

### 現在の設定（`config/initializers/rack_attack.rb`）

| キー | 制限 | 対象 |
|---|---|---|
| `req/ip` | 300req / 5min | 全リクエスト（IP 単位） |
| `admin/ip` | **60req / 5min** | `/ja/admin` 配下（IP 単位・ロケール接頭辞を許容） |
| `session/ip` | 10req / 20s | `POST .../sessions`（ログイン試行、IP 単位） |
| `sessions/login` | 10req / 20s | `POST .../sessions`（ログイン ID 単位） |

`admin/ip` はログイン試行制限とは **独立したキー** で数えるため、管理画面への大量
アクセスがログイン制限を消費することはない（その逆も同じ）。

### 実効確認（本番）

```bash
# 同一 IP から /ja/admin へ連続アクセスして 429 を確認する
for i in $(seq 1 70); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://<サーバー>/ja/admin)
  echo "$i:$code"
done | sort | uniq -c -f1 | tail

# 61 回目以降が 429（Retry-After 付き）になることを確認
curl -s -D - -o /dev/null http://<サーバー>/ja/admin | grep -E "HTTP/|Retry-After"

# rack-attack の判定は Rails ログに JSON で出る（rack_attack 通知）
docker compose -f compose.production.yaml logs --tail=100 web | grep -E "rack.attack|admin/ip"
```

期待結果: 60 回目までは `302`（未ログインのためログインへ）、61 回目以降は `429`。
IP を変えれば別カウントになる。

### 実効確認（開発環境）の重要な注意

**開発環境では `Rails.cache` が `ActiveSupport::Cache::NullStore` のため、rack-attack の
カウンタが増えず 429 は出ない。** これは rack-attack がスロットル用ストアに
`Rails.cache` を使い、`NullStore#increment` が常に `nil` を返す（コード上は 1 と
みなされる）ため。管理画面のレート制限を開発で試すには、キャッシュを有効化する。

```bash
# 開発環境でキャッシュを有効にする（memory_store に切り替わる）
touch tmp/caching-dev.txt
docker compose -f docker-compose.dev.yml restart web   # ローカル実行なら Rails を再起動

# 320 回叩いて 429 が出るか確認（caching 無効だと 302 が 320 回並ぶ）
for i in $(seq 1 320); do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/ja/admin
done | sort | uniq -c
```

なお **テスト環境（`RAILS_ENV=test`）では `Rack::Attack.enabled = false`** が既定
（`config/initializers/rack_attack.rb` の末尾）。テストで有効化する場合は
`spec/requests/admin_rate_limit_spec.rb` のように明示的に切り替える。

---

## 3. TLS 化（#121）と `FORCE_SSL`

### 現在の状態

- Caddy は `http://{$APP_DOMAIN:localhost}` で **HTTP 固定**（`Caddyfile`）。
- Rails 側も `always_use_ssl=false`・セッション Cookie の `secure=false`。

### `FORCE_SSL` の動作

`config/environments/production.rb` が次の判定で有効化する（未設定なら現状維持）。

- `FORCE_SSL` が `1` / `true` / `yes` / `on`（大文字小文字無視）
- または `APP_DOMAIN` が `https://` で始まる

有効時は次の 3 つが同時に切り替わる。

1. `config.force_ssl = true`（HTTP → HTTPS リダイレクト + HSTS + Cookie の `secure`）
2. セッション Cookie の `secure: true`（`config/initializers/session_store.rb`）
3. `/_health` はリダイレクト除外（Caddy・compose の healthcheck を壊さない）

### 入れるタイミング

**Caddyfile を HTTPS に切り替える（#121）のと同じタイミング**で入れる。

```caddyfile
# Caddyfile（#121）
#   http://{$APP_DOMAIN:localhost} {   ->   {$APP_DOMAIN:localhost} {
```

```dotenv
# .env（#121 と同じタイミング）
APP_DOMAIN=example.com
FORCE_SSL=1
# 既存の HSTS・メールリンク等の URL 生成も合わせる
   always_use_ssl=true
```

順序を間違えると、Rails が https へリダイレクトするのに Caddy が https を提供して
いない状態になり、管理画面を含む全画面が到達不能になる。

---

## 4. 管理者パスワードのローテーション（オーナー承認が必要）

実行は **オーナーが承認した上で VPS 上で** 行う。パスワードの値は表示・記録しない。

### 手順（推奨: 同梱スクリプト）

```bash
cd /opt/agent-bank
sudo bash script/rotate_admin_password.sh
# 対象ユーザーを変える場合: ADMIN_USERNAME=<username> sudo -E bash script/rotate_admin_password.sh
```

このスクリプトはランダムな 32 文字のパスワードを生成し、**一時ファイル経由**で
コンテナへ渡して `rails runner` で DB を更新する（コマンドライン引数・標準出力・
シェル履歴にパスワードを残さない）。`.env` の `ADMIN_PASSWORD` も同時に更新される。

### 手順（手動で `rails runner` を使う場合）

```bash
# 1) パスワードをファイルに作る（表示しない。umask で他ユーザーから見えないように）
(umask 077; openssl rand -base64 32 > /tmp/new_admin_pw.txt)

# 2) 更新用スクリプトを用意（値をコマンドラインに書かない）
cat > /tmp/rotate_admin_password.rb <<'RUBY'
pw = File.read("/tmp/new_admin_pw.txt").chomp
person = Person.find_by(username: ENV.fetch("ADMIN_USERNAME"))
abort("person not found") if person.nil?
person.password = pw
person.password_confirmation = pw
abort(person.errors.full_messages.join(", ")) unless person.save
puts "updated=#{person.username}"
RUBY

# 3) コンテナへ渡して実行（例: compose 構成）
docker compose -f compose.production.yaml cp /tmp/new_admin_pw.txt web:/tmp/new_admin_pw.txt
docker compose -f compose.production.yaml cp /tmp/rotate_admin_password.rb web:/tmp/rotate_admin_password.rb
docker compose -f compose.production.yaml exec -T -e ADMIN_USERNAME=<username> \
  web bundle exec rails runner /tmp/rotate_admin_password.rb

# 4) 後始末（一時ファイルを必ず消す）
docker compose -f compose.production.yaml exec -T -u root web \
  rm -f /tmp/new_admin_pw.txt /tmp/rotate_admin_password.rb
rm -f /tmp/new_admin_pw.txt /tmp/rotate_admin_password.rb
```

### 確認方法

```bash
# 新しいパスワードでログインできることを確認（302 = 成功、200 = 失敗画面）
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://<サーバー>/ja/sessions \
  --data-urlencode "person[login]=<username>" \
  --data-urlencode "person[password]=<新しいパスワード>"

# 設定中の値の確認はサーバー上でのみ（Issue・チャットには書かない）
ssh ubuntu@<サーバー> 'grep "^ADMIN_PASSWORD=" /opt/agent-bank/.env'
```

> ログイン試行は `session/ip` で 10req/20s に制限されている。確認は 1〜2 回に留める。

---

## 5. 関連ドキュメント

- Issue #120: 公開前のセキュリティ強化（本ガイドの元 Issue）
- Issue #121: ドメイン確定・TLS 化（`FORCE_SSL` と Caddyfile の切替）
- `documents/plans/20261028-vps-phase4.md`: Caddy を含む VPS 構成と起動手順
- `Caddyfile`: リバースプロキシ設定（HTTP 固定の理由と切替方法）
- `documents/plans/dev/20261103_issue120_security_hardening.md`: 本実装の計画（BDD）
