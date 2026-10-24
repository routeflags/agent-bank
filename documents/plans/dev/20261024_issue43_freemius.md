# Issue #43 本番決済（Freemius 一本）実装計画書（BDD）

- 作成日: 2026-10-24
- 対象ブランチ: `feat/agent-bank`（開始 head `0c432138c`、PR #41→main マージ後は PR #44 に反映）
- オーナー決定: **Freemius 一本。Stripe は使わない**
- 根拠ツール: `terminal: curl docs.freemius.com / freemius.com/help/* / api.freemius.com/v1/openapi.json` で公式仕様を実測 / `grep: freemius|wallet_topup|persona_purchas|STRIPE` で現行経路を特定 / `read_file: freemius_client.rb・wallet_topup_controller.rb・persona_purchases_controller.rb・freemius_webhooks_controller.rb・wallet.rb・user_plan_subscription_service.rb・spec 4件・ChatPanelApp.js` で現行規約確認 / `gh issue view/comment 43` で事実記録
- 事実記録: Issue #43 コメント `6382342198` に実装前の仕様確認済み（推測で実装しない）

## 設計分岐の結論（Issue #43 コメントと同一）

- Checkout はホスト型 `https://checkout.freemius.com/product/{product_id}/plan/{plan_id}/` が正規。サーバー API に汎用 Checkout 作成は無い（OpenAPI 全112 paths に `/checkouts` 無し）。
- **任意金額の指定は不可。plan 単位**。`POST /api/v1/wallet_topup { amount_cents }` 型の任意額チャージは Freemius 正規フローでは実現不可。persona 購入も listing ごとの `price_cents` を直接課金できず、Dashboard の plan/pricing 解決が前提。通貨は `usd|eur|gbp` のみ。
- Webhook 署名は `x-signature: HMAC-SHA256(raw_body, PRODUCT_SECRET_KEY)`。現行 `FREEMIUS_WEBHOOK_SECRET` は誤りのため寄せ替える。
- サーバー API は product スコープ `GET /products/{product_id}/payments/{payment_id}.json` 等＋ `Authorization: Bearer <API_BEARER_AUTHORIZATION_TOKEN>`。現行 `/v1/checkouts`・`/v1/payments/{id}` は実在しない。
- 実イベント名は `payment.created` / `payment.refund` / `subscription.created` / `subscription.cancelled` / `subscription.renewal.failed` 等。現行 `payment.completed` / `payment.refunded` / `subscription.renewed` / `subscription.expired` は実在しない。Payment に `status` / `amount_cents` は無く金額は `gross`（float・税抜）。

---

## タスク一覧（振る舞い単位）

### T1: FreemiusClient を product スコープに作り直す
- 振る舞い: `FreemiusClient.configured?` は `FREEMIUS_PRODUCT_ID`（数値 product_id）と Bearer（`API_BEARER_AUTHORIZATION_TOKEN`、後方互換で `FREEMIUS_API_KEY`）の両方が present のときのみ true。`get_payment(payment_id)` は `GET {base}/products/{product_id}/payments/{payment_id}.json` に Bearer で問い合わせ、parsed Hash を返す。`get_subscription` も同様。`build_hosted_checkout_url(plan_id:, user_email:, ...)` は network なしで `https://checkout.freemius.com/product/{product_id}/plan/{plan_id}/`＋query を組み立てる。`plan_id_for_listing(listing)` / `listing_id_for_plan(plan_id)` は `FREEMIUS_PLAN_MAP`（JSON）→ `FREEMIUS_PLAN_ID` の順で解決する。任意金額型の `create_checkout` / `create_persona_purchase_checkout` は廃止する。
  - 正常系: product_id `1234`＋Bearer あり → `configured? == true`。`get_payment("9876")` → `GET .../products/1234/payments/9876.json` に `Authorization: Bearer` が付き、200 の JSON を返す。例: `{ "id" => 9876, "gross" => 30.0, "currency" => "usd" }`。`build_hosted_checkout_url(plan_id: "5678", user_email: "a@x")` → `https://checkout.freemius.com/product/1234/plan/5678/?user_email=a%40x...`。
  - 異常系: product_id 又は Bearer 欠け → `configured? == false`、`get_*` は `ApiError("...not configured")`。非2xx → `ApiError("Freemius API error (code): ...")`。timeout/接続失敗 → `ApiError("...timeout/connection...")`。
  - エッジ: product_id 前後空白は strip。payment_id の `/` 等は URL escape。base URL 末尾 `/` の有無を吸収。`.json` 二重付与しない。旧 env（`FREEMIUS_API_KEY`）のみでも後方互換で動くが文書では新キーを正とする。
- 検証: `spec/services/freemius_client_spec.rb` を product スコープに書き換え（WebMock でパス・Bearer・query を検証）。旧 `/checkouts` 前提の例は削除。

### T2: ペルソナ購入は hosted checkout URL を返す（サーバーで課金は作らない）
- 振る舞い: `POST /api/v1/persona_purchases { listing_id }` は購入権利を作らない。listing 存在・有料・未購入・Freemius 設定済み・plan 解決済みのときのみ `200 { checkout_url, listing_id, plan_id, provider: "freemius" }` を返す。`checkout_url` は `FreemiusClient.build_hosted_checkout_url` の結果（`user_email`・`cancel_url` 等を付与）。金額・購入者はサーバー側で決める（client の price/user は無視）。購入完了は webhook（T3）が `UserPlanSubscriptionService.create_for(payment_reference: "freemius:<payment_id>")` で付与する。冪等。
  - 正常系: listing（price_cents 3000・JPY・未購入）に plan `5678` 解決 → 200＋hosted URL。`create_persona_purchase_checkout` は呼ばない。例データ: listing 42・user X → `checkout_url` に `/product/1234/plan/5678/` を含む。
  - 異常系: 未ログイン 401。listing 不存在 404 `listing_not_found`。無料 422 `free_listing`。購入済み → Checkout を作らず 200 `already_purchased`（UserPlanSubscription 不変）。Freemius 未設定（product/Bearer/plan のいずれか欠け）→ 503 `purchase_not_configured`（既存回帰維持）。URL 組み立て例外 → 502 `checkout_failed`。
  - エッジ: client が `amount_cents/user_id/currency` を送っても無視しサーバー値を使う。plan 未解決でも 500 にしない。`checkout_url` 欠けは 502。
- 検証: `spec/requests/api/v1/persona_purchases_spec.rb` を hosted URL 前提に更新（旧 `create_persona_purchase_checkout` スタブは廃止）。503 回帰例を残す。

### T3: webhook を実イベント・実署名・実スキーマに合わせる（冪等維持）
- 振る舞い: `POST /webhooks/freemius` は `x-signature == HMAC-SHA256(raw_post, PRODUCT_SECRET_KEY)`（後方互換で `FREEMIUS_WEBHOOK_SECRET` も許容、両方欠けは 401）のときのみ処理する。`event` は string（旧）又は `{ type }`（実）の両対応。`payment.created`（＋後方互換 `payment.completed`）→ persona/wallet に振り分け、`payment.refund`（＋ `payment.refunded`）→ refund 記録、`subscription.created/cancelled/renewal.failed`（＋旧 `renewed/expired/renewal.failed` 互換）→ state machine 同期。それ以外は 200 で ignore。persona 経路は `verify_payment`（`FreemiusClient.get_payment` で存在確認＋`gross`→cents 換算、旧 `amount_cents/amount` も許容、`status` があれば completed のみ通すが無ければ通す）の後に `create_for(freemius:<payment_id>)`。wallet 経路は `Wallet#topup!(freemius_payment_id:)`。いずれも二重配送は二重付与しない。`listing/person` 不明・payment 未検証は 200 skip（500 にしない）。
  - 正常系: 例 `payment.created { payment: { id: fs_pay_p1, gross: 30.0, currency: usd, plan_id: 5678 }, user: {...} }`＋metadata 又は plan 解決で listing 42・user X → UserPlanSubscription 1件＋初期トークン付与、`metadata` に `freemius:fs_pay_p1` を記録。wallet 例 `fs_pay_1 gross 30.0` → 残高＋3000。
  - 異常系: 署名不正/欠け → 401 で何も付与しない。payment id 欠け・wallet/listing/person 不明・未検証 → 200 skip。`get_payment` 例外 → 200 skip（再送に任せる）。
  - エッジ: `fs_pay_1` と `fs_pay_10` を混同しない（Wallet の exact match 維持）。`event: { type: ... }` と `event: "..."` の両方を受理。旧 `amount_cents` 形の payment も受理（既存 spec 互換）。
- 検証: `spec/requests/freemius_webhooks_spec.rb` を `PRODUCT_SECRET_KEY`＋実イベント名に更新し、旧名の互換例も残す。署名なし/不正 401 を維持。

### T4: ウォレットから Stripe を外し、Freemius 任意額は「不可」として外す（dev 擬似決済は残す）
- 振る舞い: `POST /api/v1/wallet_topup` は dev（`Rails.env.development?`）→ 擬似 intent（`dev_pi_*`）を返す。非 dev では Freemius/Stripe の checkout を作らず、503 `payment_unconfigured`（理由に `freemius_arbitrary_amount_unsupported` を含む趣旨）を返す。`POST /api/v1/wallet_topup/confirm` は `dev_pi_*` のみ受理し、非 dev の payment_intent は 422（Stripe 参照なし）。`GET status` は dev → `{ topup_enabled: true, provider: dev }`、非 dev → `{ topup_enabled: false, provider: nil, reason: payment_unconfigured }`。Stripe 関連 private（`create_payment_intent` / `configure_stripe_api!` / `stripe_key_configured?`）は削除する。`Wallet#auto_recharge!` 内の Stripe 直接課金は今回のフローから呼ばれない形に留め（Sharetribe コアの `PaymentSettings` 等は削除しない）、判断理由を文書に記録する。`dev_mode_topup?` の Stripe-key 条件は外す（dev は dev として判定）。
  - 正常系（開発）: `POST { amount_cents: 1000 }` → `dev_pi_*`＋`dev_mode: true`。`confirm` → 残高＋1000、二重 confirm は `amount_credited: 0`。`status` → dev。HTTP 通しで既存実績（残高 211000 等）と同等。
  - 異常系: amount 下限（100）未満・上限（10000）超過・0 → 422。未ログイン → 401。非 dev の `POST` → 503（Freemius/Stripe の checkout_url/client_secret は返さない）。非 dev の `confirm(dev_pi_以外)` → 422。
  - エッジ: 他人 uid の dev intent → 403。不正 base64 → 422。production で dev intent を送っても uid 不一致で 403（悪用で残高加算しない）。
- 検証: `spec/requests/api/v1/wallet_topup_spec.rb` の Stripe 前提例を意図的変更として更新（Stripe mock 削除、非 dev は 503、confirm は dev のみ）。dev 冪等・403・422 例は維持。

### T5: 環境変数の対応表を文書化する
- 振る舞い: `documents/guides/freemius_production_setup.md`（新規）に下表＋投入手順＋未設定時の挙動＋通貨/JPY 注意＋残件（plan 設計・固定額プリペイドの採否・本番キー投入）を記録する。`FreemiusClient` の env 名は新キー（`FREEMIUS_PRODUCT_ID` / `API_BEARER_AUTHORIZATION_TOKEN` / `PRODUCT_SECRET_KEY` / `FREEMIUS_PLAN_ID` / `FREEMIUS_PLAN_MAP` / `PRODUCT_PUBLIC_KEY`）に寄せ、旧 `FREEMIUS_API_KEY` / `FREEMIUS_WEBHOOK_SECRET` は後方互換として読む。値は書かない。
  - 正常系: 表にキー×用途（server Bearer・webhook HMAC・hosted URL product/plan・front public）×設定場所（Dashboard API & Keys / Plans / Webhooks Listener / success redirect）を明記。
  - 異常系: 未設定時は persona 503 `purchase_not_configured`・wallet 503 を維持する旨を明記。
- 検証: 文書の存在＋キー名の grep 一致（値を含まない）。

### T6: フロントは最小変更に留める
- 振る舞い: `ChatPanelApp.js` の persona 購入（hosted URL へ `assign`、503 `purchase_not_configured` 表示、already_purchased は直接 session 作成）は維持。wallet は Freemius redirect（`provider freemius＋checkout_url`）の分岐が来なくなるため、dev/503 の表示のみになる。Stripe.js へのフォールバックは追加しない。文言追加時は `ja.yml` 優先。
  - 正常系: dev wallet は従来通り modal→残高更新。persona は hosted URL へ遷移。
  - 異常系: wallet 503 → `wallet_topup_unavailable_reason` 表示。persona 503 → `purchase_not_configured` 表示。
- 検証: `cd client && npm install --ignore-scripts` → `npx webpack --mode=development --config webpack.client.config.js` が成功。生成物はコミットしない。

## 実装しないこと（Issue に記録して報告）
- ウォレットの Freemius 任意額チャージ（API に存在しないため作らない。固定額プリペイド plan 方式は代替案として文書化し、採否はオーナー判断）。
- Stripe へのフォールバック（オーナー方針で禁止）。Sharetribe コアの Stripe 連携（`PaymentSettings`・admin・旧取引フロー）の広範削除はしない（影響大のため今回フローからの参照除去に留める）。
- `PRODUCT_PUBLIC_KEY` を使う埋め込み Checkout（現行ホスト型のみで足りるため保持のみ）。
- JPY 建ての Freemius 課金（Freemius 通貨が USD/EUR/GBP のみのため、JPY 表示との整合は残件）。
