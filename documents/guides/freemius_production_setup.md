# Freemius 本番決済 環境変数対応表・運用手順（Issue #43）

- 対象: `routeflags/agent-bank`（Lamprey / 楽市楽問）、ブランチ `feat/agent-bank`
- 方針: **Freemius 一本。Stripe は使わない**（オーナー決定）
- 前提: Checkout はホスト型・plan 単位。任意金額の Checkout 作成 API は存在しない（詳細は Issue #43 コメント `6382342198`）。

## 1. 対応表（どれが何に使われるか）

| 環境変数 | 用途 | 参照元 | 備考 |
|---|---|---|---|
| `FREEMIUS_PRODUCT_ID` | Freemius product_id（数値）。サーバー API のパス `GET /products/{product_id}/...` と hosted checkout URL `.../product/{product_id}/plan/...` に使用 | Dashboard product Settings → API & Keys の product ID | **現 `.env` に未存在**。本番投入時に Dashboard から取得して追加すること。値はコミット・報告に書かない |
| `API_BEARER_AUTHORIZATION_TOKEN` | サーバー API の Bearer トークン（`Authorization: Bearer`）。`get_payment` / `get_subscription` の認証に使用 | Dashboard product Settings → API & Keys → API Bearer Authorization Token | 32 文字。`.env` に設定済み。旧名 `FREEMIUS_API_KEY` も後方互換で読むが、新規は本キーを使うこと |
| `PRODUCT_SECRET_KEY` | Webhook `x-signature`（HMAC-SHA256(raw_body, secret)）と success redirect `signature`（HMAC-SHA256(clean_url, secret)）の検証鍵 | Dashboard product Settings → API & Keys → Secret Key | 32 文字。`.env` に設定済み。旧名 `FREEMIUS_WEBHOOK_SECRET` も後方互換で読むが、新規は本キーを使うこと。公開・コミット厳禁 |
| `PRODUCT_PUBLIC_KEY` | フロント公開鍵（Buy Button / checkout.js の公開側）。現行のホスト型リダイレクトのみの運用ではサーバーは使わない。将来の埋め込み Checkout 用に保持 | Dashboard product Settings → API & Keys → Public Key | 32 文字。`.env` に設定済み |
| `FREEMIUS_PLAN_ID` | 単一 plan 運用時の既定 plan_id（persona 購入の hosted URL 生成に使用） | Dashboard Plans で作成した plan の ID | 未設定時は persona 購入は 503 `purchase_not_configured`。per-listing 運用では `FREEMIUS_PLAN_MAP` が優先 |
| `FREEMIUS_PLAN_MAP` | listing ごとの plan 対応（JSON）。例: `{"42":"5678"}`（listing 42 → plan 5678） | Dashboard Plans × Listing 対応表を運用で管理 | 任意。単一 plan で足りる間は不要。Webhook の `plan_id → listing_id` 逆引きにも使う |
| `FREEMIUS_API_BASE_URL` | サーバー API 基底 URL（既定 `https://api.freemius.com/v1`）。テストのスタブ用 | 既定値で可 | 旧 `FreemiusClient` の `/v1/checkouts` 前提は廃止済み |
| `FREEMIUS_API_KEY`（旧） | `API_BEARER_AUTHORIZATION_TOKEN` の旧名。後方互換で読むのみ | — | 新規設定は `API_BEARER_AUTHORIZATION_TOKEN` を使うこと |
| `FREEMIUS_WEBHOOK_SECRET`（旧） | `PRODUCT_SECRET_KEY` の旧名。後方互換で読むのみ | — | 新規設定は `PRODUCT_SECRET_KEY` を使うこと |

`FreemiusClient` の env 名は新キーに寄せている。旧キーは `configured?` / `webhook_secret` / `bearer_token` のフォールバックとしてのみ読む。

## 2. Dashboard 側の設定手順（コード変更なしで運用がすること）

1. Developer Dashboard で product を確認し、`FREEMIUS_PRODUCT_ID`・`API_BEARER_AUTHORIZATION_TOKEN`・`PRODUCT_SECRET_KEY`・`PRODUCT_PUBLIC_KEY` を取得して本番 Secrets に投入する。
2. Plans/Pricing で persona 購入用の plan を作成する（価格・通貨 `USD` 前提。Freemius 通貨は `USD/EUR/GBP` のみで `JPY` 建て不可）。単一価格なら `FREEMIUS_PLAN_ID` に設定し、価格帯が複数ある場合は `FREEMIUS_PLAN_MAP` に listing 対応を記録する。
3. Webhooks Listener を作成し、URL `https://<本番ドメイン>/webhooks/freemius` を登録する。対象イベントは少なくとも `payment.created`・`payment.refund`・`subscription.created`・`subscription.cancelled`・`subscription.renewal.failed` を含める。署名方式は既定（`x-signature`）でよい。
4. Plans → Customization で success redirect（Redirect Checkout to a custom URL）を必要に応じて設定する。`user_id`・`plan_id`・`payment_id`・`license_id`・`amount`・`signature` が query に付与される。`signature` は `PRODUCT_SECRET_KEY` で検証できる。
5. 実際のカード決済は行わず、checkout リンク生成（`POST /api/v1/persona_purchases` → `checkout_url`）と Dashboard の Events 一覧、サーバー API 到達性（`GET /products/{id}/payments/{id}.json`）までを確認する。

## 3. 未設定時の挙動（回帰維持）

- `FREEMIUS_PRODUCT_ID` 又は Bearer 欠け、又は plan 未解決 → `POST /api/v1/persona_purchases` は 503 `purchase_not_configured`（購入権利は作らない）。
- 非開発環境の `POST /api/v1/wallet_topup` は 503 `payment_unconfigured`（理由 `freemius_arbitrary_amount_unsupported` 付き）。`GET status` は `topup_enabled: false`。開発環境では擬似決済（`dev_pi_*`）が従来どおり動作する。

## 4. ウォレット任意額チャージを Freemius で実現しない理由と代替案

- 理由: Freemius に任意金額の Checkout 作成 API が存在しない（OpenAPI 全112 paths に `/checkouts` 無し、checkout 系は hosted link 組み立て・checkout token・license upgrade link のみ）。ホスト型・JS SDK とも `planId` 必須で `amount` 指定不可。通貨も `usd|eur|gbp` のみ。よって `amount_cents` 自由指定のチャージは正規フローで実現不可。無理に作らず Freemius 分岐を外している。
- 代替案（採否はオーナー判断）:
  1. 固定額プリペイド plan 方式: 例 `500 / 1,000 / 3,000 / 10,000` の固定額 plan を Dashboard に作り、フロントで金額選択→対応 plan の hosted URL へ遷移、webhook `payment.created` で `gross` 分をチャージする。要 `FREEMIUS_PLAN_MAP` 拡張と金額×plan の運用管理。
  2. ペルソナ購入に集約: チャージ概念をやめ、購入は persona 単位の hosted checkout のみにする。残高・従量課金の運用を見直す必要がある。
  3. 当面は開発用擬似決済のみ: 本番の金銭授受が発生するまで `topup_enabled: false` のままにし、購入付与は `dev` 経路・手動付与 rake・運用手作業でまかなう。
- Stripe へはフォールバックしない（オーナー方針）。

## 5. Stripe 除去の判断記録

- ペルソナ購入・ウォレットの経路から Stripe を外した（`create_payment_intent` / `confirm` の Stripe 分岐 / `stripe_key_configured?` / `configure_stripe_api!` を削除）。理由: オーナー方針（Freemius 一本）と、Freemius MoR 前提ではカード情報を自前で扱わないため。
- 広範な削除はしていない: Sharetribe コアの Stripe 連携（`PaymentSettings`・admin 画面・旧取引フロー・`stripe_service`・`Wallet#auto_recharge!` の Stripe 呼び出し等）は影響が大きいため残している。今回のフロー（persona 購入・wallet topup/confirm/status）からは参照しない形に留めた。`auto_recharge!` の Stripe 直接課金は本 Issue の対象外とし、自動チャージを有効化する場合は別途 Freemius 方式（手動チャージ誘導 or 固定額 plan）の検討が必要（残件）。

## 6. 通貨・残件（オーナー判断が必要なもの）

- `config/billing.yml` の既定通貨は `USD` のまま（Freemius 通貨に合わせるため）。UI の円表示との不整合（Issue #43 補足）は本 Issue では直していない。JPY 建て課金は Freemius で不可のため、価格表示・請求通貨の方針決定が必要。
- plan 設計: persona ごとの価格（`listing.price_cents`）をどの plan/pricing に対応させるか。単一 plan（`FREEMIUS_PLAN_ID`）で始めるか、価格帯ごとに plan を作り `FREEMIUS_PLAN_MAP` で管理するかを決定すること。
- 固定額プリペイド（ウォレット）の採否: 上記 4 の代替案 1 を採用するかどうか。
- 本番キー投入手順: `FREEMIUS_PRODUCT_ID` の取得と Secrets 投入、Webhook Listener 登録、success redirect 設定、サンドボックスでの checkout 到達確認。実際のカード決済は本 Issue の検証範囲外。

## 出典

- https://freemius.com/help/api/（Bearer Token Authentication / Making API Requests / Other Scopes and Authentication）
- https://api.freemius.com/v1/openapi.json（product スコープのパス形、`/checkouts` 不存在の実測）
- https://freemius.com/help/documentation/checkout/integration/hosted-checkout/（hosted URL schema、plan 必須、通貨 `usd|eur|gbp`、Verifying the Data）
- https://freemius.com/help/documentation/saas-sdk/js-sdk/checkout/（`freemius.checkout.create({ user, planId })`）
- https://freemius.com/help/documentation/marketing-automation/events-webhooks/（Validating Webhook Signatures: `x-signature` + HMAC-SHA256 + product secret key、Types of Events）
- https://freemius.com/help/documentation/saas-sdk/js-sdk/webhooks/（`x-signature` 検証、`processFetch/processNodeHttp`）
