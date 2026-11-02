# Issue #120 セキュリティ強化 — 実装計画（BDD）

- 対象 Issue: routeflags/agent-bank#120「公開前のセキュリティ強化（管理者資格情報・管理画面の保護・レート制限）」
- 作業ブランチ: `feat/120-security-hardening`（`origin/main` = `f60379efb` から分岐）
- スコープ: Issue 本文のうち **コードで実装できる 3 点**
  - A: `/admin` 配下の **IP 許可リスト制限**
  - B: rack-attack の `/admin` 専用 throttle
  - C: `FORCE_SSL` スイッチ（`force_ssl` + セッション Cookie の `secure`）
  - D: 運用手順ドキュメント（`documents/guides/security_hardening.md`）
- スコープ外（親が実施）: 管理者パスワードのローテーション（オーナー承認が必要）、
  本番 `.env` への反映、Caddyfile の TLS 切替（#121）

> **スコープ変更（オーナー判断・実装中）**: A の Basic 認証は実装しない。
> `/admin` の保護は **IP 許可リスト（`ADMIN_ALLOWED_IPS`）のみ** とする。

## 0. 前提の確認（読んだ実装）

| 確認したこと | 手段 / 参照 |
|---|---|
| `Admin2::AdminBaseController` は admin2 配下 56 コントローラの共通親。`ensure_is_admin` を宣言 | `app/controllers/admin2/admin_base_controller.rb` |
| 管理画面ルートは `scope module: "admin2", path: "/admin"`。`/ja/admin` のようにロケール接頭辞が付く | `config/routes.rb:178` |
| rack-attack 6.6.1。`req/ip` 300/5min、`session/ip`・`sessions/login` 10/20s。テストでは `self.enabled = false` | `config/initializers/rack_attack.rb` |
| rack-attack のストアは `Rails.cache`。開発は `tmp/caching-dev.txt` が無いと `:null_store` → `increment` が `nil` を返し `count` は常に 1 = **throttle が効かない**（実測でも 320 回すべて 302） | `config/environments/development.rb:74-85`、`rack-attack-6.6.1/lib/rack/attack/cache.rb` |
| セッション Cookie の `secure` は既に `APP_CONFIG.always_use_ssl` 由来 | `config/initializers/session_store.rb:71` |
| HTTP→HTTPS リダイレクトは `EnforceSsl` ミドルウェア（`APP_CONFIG.always_use_ssl`）。`/_health` は Rails 内で完結 | `lib/rack_middleware/enforce_ssl.rb`、`config/application.rb:104` |
| 本番 Caddy は `http://{$APP_DOMAIN:localhost}` で **HTTP 固定**、`web:3000` へ転送。`/_health` も HTTP で転送 | `Caddyfile:20-21` |
| `trusted_proxies` は既定（未設定）→ Rails 既定の private/loopback を信頼するため、Caddy が付ける `X-Forwarded-For` から `remote_ip` がクライアント IP になる | `config/application.rb:91`、`config/config.defaults.yml` に定義なし |
| テスト用 `Rails.cache` は `:memory_store` | `config/environments/test.rb:60` |
| 既存 admin2 request spec は view 描画（200）を検証しているが、この作業ツリーには webpack 成果物（`vendor-bundle`）が無く **既存 spec も失敗する**（環境依存の既存制約）。`spec/requests/admin2_general_spec.rb` で再現確認 | `log/test.log` の `Sprockets::FileNotFound` |

## 1. BDD タスク一覧（振る舞い単位）

### A. `/admin` の IP 許可リスト制限

判定ロジックは `app/services/admin_access_control.rb`（PORO・クラスメソッド）に置き、
コントローラは `prepend_before_action` から呼ぶ。

| # | 振る舞い | 分類 | 仕様例（データ） |
|---|---|---|---|
| A-1 | `ADMIN_ALLOWED_IPS` 未設定 → 何もしない（従来どおり `ensure_is_admin` が動く） | 正常系 | ENV 未設定 / `""` 空文字 |
| A-2 | 許可 IP からのアクセス → 通過（未ログインなら従来どおりログインへ 302） | 正常系 | `ADMIN_ALLOWED_IPS=127.0.0.1`、remote_ip `127.0.0.1` |
| A-3 | CIDR 許可内 → 通過 | 正常系 | `ADMIN_ALLOWED_IPS=203.0.113.0/24`、remote_ip `203.0.113.42` |
| A-4 | 許可外 IP → **403**（ログイン画面へリダイレクトしない） | 異常系 | `ADMIN_ALLOWED_IPS=203.0.113.0/24`、remote_ip `198.51.100.7` |
| A-5 | `0.0.0.0/0` は全許可（IP 制限を実質無効化） | エッジ | `ADMIN_ALLOWED_IPS=0.0.0.0/0`、任意 IP |
| A-6 | 複数指定（IP と CIDR の混在、空白入り） | エッジ | `"127.0.0.1, 203.0.113.0/24"` |
| A-7 | IPv6（`::1` など）も指定・判定できる | エッジ | `"::1,203.0.113.10"` |
| A-8 | 解析できない値だけが設定されている → **全拒否（403）** + 警告ログ（設定ミスで保護が無効にならない） | エッジ | `ADMIN_ALLOWED_IPS=not-an-ip` |
| A-9 | 一部だけ不正 → 解釈できた分だけ有効 | エッジ | `"127.0.0.1,not-an-ip"` |
| A-10 | `remote_ip` が nil / 不正 → 拒否（fail closed） | エッジ | `request.remote_ip` が nil |
| A-11 | IPv4 射影 IPv6（`::ffff:127.0.0.1`）は IPv4 として判定 | エッジ | `ADMIN_ALLOWED_IPS=127.0.0.1` |
| A-12 | 保護の対象は管理画面のみ（一般画面は 403 にならない） | 正常系 | `ADMIN_ALLOWED_IPS` 設定中の `GET /ja` |

### B. rack-attack の `/admin` 専用 throttle

| # | 振る舞い | 分類 | 仕様例 |
|---|---|---|---|
| B-1 | 同一 IP から `/admin` 配下へ 5 分間に 60 回超 → **429**（61 回目） | 正常系 | `GET /ja/admin` × 61 |
| B-2 | `/admin` の制限はログイン試行制限（`session/ip`）と独立 | 正常系 | `/admin` で 429 の後、`POST /ja/sessions` は 429 にならない |
| B-3 | `/admin` 以外のパスは `/admin` throttle の対象外 | 正常系 | `/admin` で 429 の後、`GET /ja` は 429 にならない |
| B-4 | `/admin2`（旧 URL リダイレクト）や `/administrators` を巻き込まない | エッジ | `Rack::Attack.admin_path?` の単体テスト |
| B-5 | テスト環境では従来どおり `Rack::Attack.enabled = false`（spec 内で明示的に有効化） | 回帰 | `spec/requests/admin_rate_limit_spec.rb` |

### C. セッション Cookie の `secure` フラグ（TLS 準備）

| # | 振る舞い | 分類 | 仕様例 |
|---|---|---|---|
| C-1 | `FORCE_SSL=1` → `config.force_ssl = true` と セッション Cookie `secure: true` | 正常系 | `FORCE_SSL=1` |
| C-2 | `APP_DOMAIN` が `https://` で始まる → 同上 | 正常系 | `APP_DOMAIN=https://example.com` |
| C-3 | どちらも未設定 → 現状維持（`force_ssl` false・Cookie `secure` false） | 正常系 | ENV 未設定 |
| C-4 | `FORCE_SSL=0` / `false` / 空文字は無効 | エッジ | `FORCE_SSL=0` |
| C-5 | `/_health` は HTTP のまま通す（Caddy の healthcheck を壊さない） | エッジ | `ssl_options[:redirect][:exclude]` |
| C-6 | 既存の Redis キャッシュ設定（Issue #99 の REDIS_URL 一本化）に触れない | 回帰 | `production.rb` の差分が最小であること |

### D. ドキュメント

`documents/guides/security_hardening.md` に、IP 制限の有効化手順（`ADMIN_ALLOWED_IPS` の
設定例: 自宅 IP / 社用 IP のカンマ区切り、`::1` など IPv6 の扱い）、rack-attack の実効確認、
管理者パスワードのローテーション手順（値は書かない）、`FORCE_SSL` と TLS（#121）の関係を記載。

## 2. 実装方針（要点）

1. **未設定なら何もしない**: `before_action` の入口で「ENV が空なら return」。
   メソッド内で判定するため、ENV の実行時切替（spec・`rails runner`）に追従する。
2. **`prepend_before_action`**: `ensure_is_admin`（302）より先に 403 を返すため。
3. **fail closed**: 設定が壊れている（解析不能・`remote_ip` 不明）場合は拒否。
4. **Blast radius 最小**: C は `production.rb` に十数行、`session_store.rb` は `||` 1 箇所。
5. **Basic 認証は入れない**（オーナー判断）。

## 3. 検証計画

- `bundle exec rspec` で追加 spec + 既存 admin2 / session 関連 spec の回帰。
- `bundle exec rails runner` で ENV を切り替えた実測（development、Rails サーバーは起動しない）:
  - Rack::Test で `Rails.application` に対して /ja/admin を叩き、403 / 302 を確認。
  - rack-attack は development が `:null_store` のため 429 が出ないことを実測し、
    429 の確認は test 環境（memory_store）で行う。
- `RAILS_ENV=production` の runner で `FORCE_SSL` の ON/OFF を実測（`secret_key_base` は
  一時的なダミー値を環境変数で渡すだけ。リポジトリ・DB には残さない）。

## 4. 検証結果（実測）

| 検証 | コマンド | 結果 |
|---|---|---|
| 追加 spec | `bundle exec rspec spec/services/admin_access_control_spec.rb spec/requests/admin_access_control_spec.rb spec/requests/admin_rate_limit_spec.rb spec/lib` | **31 examples, 0 failures** |
| 既存 spec の回帰（`spec/services`・`spec/middleware`・`http_basic_auth`・`https_redirects`・`hsts`） | 同コマンドを `origin/main`（`f60379efb`）と本ブランチで実行し JSON で比較 | 失敗 15 件が **完全一致**（webpack 成果物不足による 500 と Delayed::Job の環境制約。いずれも既存） |
| 管理画面コントローラ | `bundle exec rspec spec/controllers/admin2` | 97 examples, 4 failures（すべて "Delayed job failed" = ローカル環境の既存制約） |
| RuboCop | 変更ファイル 9 件 | no offenses |
| A: 実測（development） | `RAILS_ENV=development bundle exec rails runner` + `Rack::Test`（サーバー起動なし） | 未設定 302 / CIDR 外 403 / CIDR 内 302 / `0.0.0.0/0` 302 / `::1` 302 / `not-an-ip` 403 / 空文字 302 |
| B: 実測（development） | 同上で `/ja/admin` を 320 回 | すべて 302（`Rails.cache` が `NullStore` のため throttle は不発。ドキュメントに明記） |
| B: 429（test） | `spec/requests/admin_rate_limit_spec.rb` | 60 回まで 302、61 回目 429。`/ja` と `POST /ja/sessions` は 429 にならない |
| C: 実測（production 設定の boot） | `RAILS_ENV=production ... rails runner`（`secret_key_base` は一時的な環境変数のみ） | 未設定: `force_ssl=false` / `session secure=false`、`FORCE_SSL=1`: `force_ssl=true` / `session secure=true` / `/_health` はリダイレクト除外 |

**作ったデータの後始末**: テストデータは FactoryBot + DatabaseCleaner（トランザクション）で
各 example 終了時にロールバック。development への実測は GET のみで書き込みなし。
`rails runner` で使った `secret_key_base` はコマンド内の一時値（ファイル・DB に残していない）。
