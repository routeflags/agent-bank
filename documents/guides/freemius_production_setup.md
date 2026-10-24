# Freemius 本番決済 環境変数対応表・運用手順（Issue #43）

- 対象: `routeflags/agent-bank`（Lamprey / 楽市楽問）、ブランチ `feat/agent-bank`
- 方針: **Freemius 一本。Stripe は使わない**（オーナー決定）
- 前提: Checkout はホスト型・plan 単位。任意金額の Checkout 作成 API は存在しない（詳細は Issue #43 コメント `6382342198`）。

## 1. 対応表（どれが何に使われるか）

| 環境変数 | 用途 | 参照元 | 備考 |
|---|---|---|---|
| `PRODUCT_ID` | Freemius product_id（数値）。サーバー API のパス `GET /products/{product_id}/...` と hosted checkout URL `.../product/{product_id}/plan/...` に使用。旧名 `FREEMIUS_PRODUCT_ID` も後方互換で読む | Dashboard product Settings → API & Keys の product ID | 設定済み（`.env`）。値はコミット・報告に書かない |
| `API_BEARER_AUTHORIZATION_TOKEN` | サーバー API の Bearer トークン（`Authorization: Bearer`）。`get_payment` / `get_subscription` の認証に使用 | Dashboard product Settings → API & Keys → API Bearer Authorization Token | 32 文字。`.env` に設定済み。旧名 `FREEMIUS_API_KEY` も後方互換で読むが、新規は本キーを使うこと |
| `PRODUCT_SECRET_KEY` | Webhook `x-signature`（HMAC-SHA256(raw_body, secret)）と success redirect `signature`（HMAC-SHA256(clean_url, secret)）の検証鍵 | Dashboard product Settings → API & Keys → Secret Key | 32 文字。`.env` に設定済み。旧名 `FREEMIUS_WEBHOOK_SECRET` も後方互換で読むが、新規は本キーを使うこと。公開・コミット厳禁 |
| `PRODUCT_PUBLIC_KEY` | フロント公開鍵（Buy Button / checkout.js の公開側）。現行のホスト型リダイレクトのみの運用ではサーバーは使わない。将来の埋め込み Checkout 用に保持 | Dashboard product Settings → API & Keys → Public Key | 32 文字。`.env` に設定済み |
| `PLAN_ONETIME_ID` | persona 購入の既定 plan_id（一括購入）。listing 個別指定 > `FREEMIUS_PLAN_MAP` > 本キー > `FREEMIUS_PLAN_ID` の順で解決 | Dashboard Plans の one-time plan ID | `.env` に設定済み（5 桁）。実測: この plan で hosted checkout が 200 で開くことを確認 |
| `PLAN_MONTHLY_ID` | 月次 plan_id。**現行コードでは未参照**（サブスクリプション課金を入れる際に使う予定） | Dashboard Plans の monthly plan ID | `.env` に設定済み。利用する機能を決めてから配線する |
| `STORE_ID` / `STORE_PUBLIC_KEY` / `STORE_SECRET_KEY` | Freemius **store** スコープの識別子と鍵。`GET /v1/stores/{id}.json?public_key=...` は 200 で返ることを実測確認済み。**現行の product スコープ実装では未使用** | Store Settings → API & Keys | 将来 store 単位の集計・商品一覧を扱う場合に使う。値はコミット・報告に書かない |
| `FREEMIUS_PLAN_ID` | 単一 plan 運用時の既定 plan_id（persona 購入の hosted URL 生成に使用）。`PLAN_ONETIME_ID` が優先 | Dashboard Plans で作成した plan の ID | 未設定時は persona 購入は 503 `purchase_not_configured`。per-listing 運用では `FREEMIUS_PLAN_MAP` が優先 |
| `FREEMIUS_PLAN_MAP` | listing ごとの plan 対応（JSON）。例: `{"42":"5678"}`（listing 42 → plan 5678） | Dashboard Plans × Listing 対応表を運用で管理 | 任意。単一 plan で足りる間は不要。Webhook の `plan_id → listing_id` 逆引きにも使う |
| `FREEMIUS_API_BASE_URL` | サーバー API 基底 URL（既定 `https://api.freemius.com/v1`）。テストのスタブ用 | 既定値で可 | 旧 `FreemiusClient` の `/v1/checkouts` 前提は廃止済み |
| `FREEMIUS_JPY_USD_RATE` | JPY→USD 換算レート（1 JPY = 何 USD か。例 `0.0067`）。`FreemiusPricing` が読み、`POST /api/v1/persona_purchases` の換算と出品ページの USD 目安表示に使用 | オーナーが投入（値はコミット・報告に書かない） | **未設定・不正値時は本番課金を 503 `payment_unconfigured` で拒否**。既定レートでの黙認課金はしない。dev 擬似決済はレート不要 |
| `FREEMIUS_PLAN_PRICE_MAP`（任意） | plan 価格の対応表（JSON。例 `{"5678":1999}` = plan 5678 は 1999 USD cents）。換算値との乖離チェックに使用 | 価格帯が複数ある場合に運用で管理 | 未設定時はチェックなし（`:unknown`）。壊れた JSON も `{}` 扱い |
| `FREEMIUS_TOPUP_PLAN_MAP` | 固定額プリペイドの額面対応表（JSON。例 `{"5678":1000,"5679":3000}` = plan 5678 で 1,000円分、plan 5679 で 3,000円分をチャージ）。`GET status` の額面一覧・`POST` の plan 解決・webhook の付与額の唯一の正 | Dashboard で額面 plan を作り plan_id と付与円額を対応付けて投入（#46） | 未設定・空・壊れた JSON・空オブジェクト・不正値（非正整数・100〜100,000円範囲外）・重複キー・persona plan との重複はすべて「未設定」扱いで本番チャージは 503。値はコミット・報告に書かない |
| `FREEMIUS_PRICE_TOLERANCE_PCT`（任意） | 乖離チェックの許容差（%、既定 `20`） | 既定で可 | 数値以外は既定値にフォールバック |
| `FREEMIUS_API_KEY`（旧） | `API_BEARER_AUTHORIZATION_TOKEN` の旧名。後方互換で読むのみ | — | 新規設定は `API_BEARER_AUTHORIZATION_TOKEN` を使うこと |
| `FREEMIUS_WEBHOOK_SECRET`（旧） | `PRODUCT_SECRET_KEY` の旧名。後方互換で読むのみ | — | 新規設定は `PRODUCT_SECRET_KEY` を使うこと |

`FreemiusClient` の env 名は新キーに寄せている。旧キーは `configured?` / `webhook_secret` / `bearer_token` のフォールバックとしてのみ読む。

## 2. Dashboard 側の設定手順（コード変更なしで運用がすること）

1. Developer Dashboard で product を確認し、`FREEMIUS_PRODUCT_ID`・`API_BEARER_AUTHORIZATION_TOKEN`・`PRODUCT_SECRET_KEY`・`PRODUCT_PUBLIC_KEY` を取得して本番 Secrets に投入する。
2. Plans/Pricing で persona 購入用の plan を作成する（価格・通貨 `USD` 前提。Freemius 通貨は `USD/EUR/GBP` のみで `JPY` 建て不可）。単一価格なら `FREEMIUS_PLAN_ID` に設定し、価格帯が複数ある場合は `FREEMIUS_PLAN_MAP` に listing 対応を記録する。
3. Webhooks Listener を作成し、URL `https://<本番ドメイン>/webhooks/freemius` を登録する。対象イベントは少なくとも `payment.created`・`payment.refund`・`subscription.created`・`subscription.cancelled`・`subscription.renewal.failed` を含める。署名方式は既定（`x-signature`）でよい。
4. Plans → Customization で success redirect（Redirect Checkout to a custom URL）を必要に応じて設定する。`user_id`・`plan_id`・`payment_id`・`license_id`・`amount`・`signature` が query に付与される。`signature` は `PRODUCT_SECRET_KEY` で検証できる。
5. 実際のカード決済は行わず、checkout リンク生成（`POST /api/v1/persona_purchases` → `checkout_url`）と Dashboard の Events 一覧、サーバー API 到達性（`GET /products/{id}/payments/{id}.json`）までを確認する。

## 3. 未設定時の挙動（回帰維持・#46 更新）

- `FREEMIUS_PRODUCT_ID` 又は Bearer 欠け、又は plan 未解決 → `POST /api/v1/persona_purchases` は 503 `purchase_not_configured`（購入権利は作らない）。
- 換算レート（`FREEMIUS_JPY_USD_RATE`）欠け・不正値 → `POST /api/v1/persona_purchases` は 503 `payment_unconfigured`（`reason: "fx_rate_unconfigured"` 付き、checkout URL は作らない）。既定レートでの無断課金はしない。
- `POST /api/v1/wallet_topup`（#46）: `plan_id` ありで Freemius/Bearer・レート・`FREEMIUS_TOPUP_PLAN_MAP` のいずれか欠け → 503 `payment_unconfigured`（`reason: freemius_not_configured / fx_rate_unconfigured / topup_plans_unconfigured`）。`plan_id` 不明 → 422 `invalid_plan`。`plan_id` なし（任意額 `amount_cents` 等）は非開発で 422 `plan_id_required`（任意額は受け付けない）。開発環境では `amount_cents` の擬似決済（`dev_pi_*`）が従来どおり動作する（`plan_id` 不要の経路を残す・換算レート不要）。
- `GET /api/v1/wallet_topup/status`: 固定額が使える条件（Freemius 設定済み＋レート設定済み＋TOPUP_MAP 有効）を満たすとき `topup_enabled: true, provider: "freemius", denominations: [...]`。開発は `topup_enabled: true, dev_mode: true` を維持し、固定額が使えるときは `denominations` も併せて返す。いずれも不可なら `topup_enabled: false, reason: "payment_unconfigured"`。

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

- ~~`config/billing.yml` の既定通貨は `USD` のまま（Freemius 通貨に合わせるため）。UI の円表示との不整合（Issue #43 補足）は本 Issue では直していない。JPY 建て課金は Freemius で不可のため、価格表示・請求通貨の方針決定が必要。~~ → **決定済み（オーナー）: 円価格を USD に換算して請求する。換算レートは `FREEMIUS_JPY_USD_RATE`。** 詳細は下記 §7。`config/billing.yml` の既定通貨は `USD` のまま。
- ~~plan 設計: persona ごとの価格（`listing.price_cents`）をどの plan/pricing に対応させるか。単一 plan（`FREEMIUS_PLAN_ID`）で始めるか、価格帯ごとに plan を作り `FREEMIUS_PLAN_MAP` で管理するかを決定すること。~~ → **維持: `listing.freemius_plan_id` → `FREEMIUS_PLAN_MAP` → `FREEMIUS_PLAN_ID` の優先順位。** Dashboard の plan 価格と換算値の対応方法は下記 §7。
- 固定額プリペイド（ウォレット）の採否: 上記 4 の代替案 1 を採用するかどうか。 → **採用（オーナー決定・#46）: (a) 固定額プリペイドと (b) ペルソナ直接購入の両方を実装。** 詳細は下記 §8。
- 本番キー投入手順: `FREEMIUS_PRODUCT_ID` の取得と Secrets 投入、Webhook Listener 登録、success redirect 設定、サンドボックスでの checkout 到達確認。実際のカード決済は本 Issue の検証範囲外。

## 7. JPY→USD 換算（`FREEMIUS_JPY_USD_RATE`）

- 換算の単一入り口: `FreemiusPricing`（`app/services/freemius_pricing.rb`）。#46（固定額プリペイド）もここを再利用する。
- 換算式: `usd_cents = ceil(円 × rate × 100)`（BigDecimal で計算）。`1 USD = 100 cents`。`listing.price_cents` は円額として扱う（JPY に補助通貨なし）。例: rate `0.0067` のとき 3000円 → 2010 cents（$20.10）。
- 丸め: 最小通貨単位（1 cent）で**切り上げ**。理由は表示円額に対して不足徴収にしないため。境界値: 0円 → 0、1円 × 0.0067 = 0.67 → 1、端数（100円 × 0.00673 = 67.3）→ 68、巨大額（9,999,999円）→ 6,700,000、負数 → 0。spec（`spec/services/freemius_pricing_spec.rb`）で固定。
- 未設定時の挙動: 欠け・空・非数値・0・負・NaN/Infinity はすべて「未設定」扱い。本番の persona 購入は 503 `payment_unconfigured`（`reason: fx_rate_unconfigured`）で checkout を作らない。既定値で黙って課金しない。開発の dev 擬似決済は従来どおり（レート不要）。
- API の返却値（`POST /api/v1/persona_purchases` の 200）: 既存 `checkout_url/plan_id/listing_id/amount_cents（JPY・互換維持）/provider` に加え、`amount_jpy`・`amount_usd_cents`・`currency: "usd"`・`fx_rate` を返す。フロントは USD 額（目安）を表示してから checkout へ遷移する。出品ページの価格ボックスにも USD 目安行を出す（レート設定時のみ）。
- plan との対応方法: Freemius plan の価格は Dashboard 側で固定 USD。換算値は「どの plan を選ぶか」「購入者にいくらと表示するか」の目安に使う。運用の目安式: `plan価格(USD) ÷ rate ≒ 円価格`。例: rate `0.0067` で 3000円の persona には約 $20.10 → Dashboard で $19.99 等の tier plan を作り `FREEMIUS_PLAN_MAP` で対応付ける。
- 乖離時の扱い: 任意 env `FREEMIUS_PLAN_PRICE_MAP`（`{"<plan_id>": <usd_cents>}`）がある場合のみ、`FREEMIUS_PRICE_TOLERANCE_PCT`（既定 20%）で照合する。超過は警告ログ（`[FreemiusPricing] plan price drift`）に留め、200 を継続して遮断しない。理由: 真の請求額は hosted checkout 画面が購入者に示すため、為替変動・tier 価格での誤遮断を避ける。map 未設定時は運用目視（Dashboard 価格 × レート逆算の対応表）で確認する。

## 8. 固定額プリペイド＋直接購入の併用（Issue #46・オーナー決定）

- 方針: **(a) 固定額プリペイドと (b) ペルソナ直接購入の両方を実装** する。既定の導線は直接購入。残高は「先にチャージして使う」任意の前払い。チャットのトークン消費は残高から引く（現行どおり）。
- 額面 plan の運用: Dashboard に額面 plan を複数作る（例: USD 5 / 10 / 30 相当）。`FREEMIUS_TOPUP_PLAN_MAP`（JSON `{ "<plan_id>": <付与クレジット(円)> }`）で plan → 付与額を解決する。これを唯一の正とし、起動時（initializer）＋参照時（`FreemiusTopupPlans.validation_errors`）に欠落・重複・不正値を検証する。persona plan（`FREEMIUS_PLAN_MAP` / `FREEMIUS_PLAN_ID`）との plan_id 重複はエラー（webhook は persona 優先のため、重複 plan は wallet に届かない）。
- API:
  - `GET /api/v1/wallet_topup/status` は購入可能な額面一覧（`plan_id` / `credit_jpy` / `estimated_usd_cents` / `currency: "usd"` / `fx_rate` / `plan_price_usd_cents`）を返す。換算は `FreemiusPricing` のみを使う（新しい換算ロジックは書かない）。通貨は USD 固定。円表示は換算値であり、レート変動で表示が変わることを UI（`topup_fx_note`）・文書で明示する。
  - `POST /api/v1/wallet_topup` は `plan_id` を受け取りホスト型 Checkout URL を返す。任意額 `amount_cents` は 422（`plan_id_required`）。開発の擬似決済（`amount_cents` → `dev_pi_*` → `confirm`）は従来どおり（`plan_id` 不要）。
  - webhook `payment.created`: `plan_id` → 付与クレジット（円）を `FREEMIUS_TOPUP_PLAN_MAP` から解決し `Wallet#topup!` で加算。`freemius:<payment_id>` の厳密一致で冪等（二重配送で二重加算しない・`fs_pay_1` と `fs_pay_10` の混同なし）。plan 不明は加算しない。plan なしの legacy は検証済み gross を加算（既存テスト互換）。
- ホスト型 Checkout はサーバー側で metadata を付けられないため、webhook の local ユーザー特定は次の順序で行い、取り違えが起きないことを spec で固定する: 明示 `wallet_id` → 明示 `user_id`（local id）→ `user_email` の厳密一致（`Person.by_email` の `WHERE address = ?`・lowercase exact、前方一致なし）。`objects.user.email` / `payment.user_email` / `payment.user.email` を見る。plan_id 逆引き（`listing_id_for_plan`）は persona 判定にのみ使い、wallet 解決には使わない。
- (b) 直接購入: 既存 `POST /api/v1/persona_purchases` を維持。残高の有無に依存しない（残高ゼロでも checkout URL を返す）。購入済み `already_purchased` 挙動を維持。UI は「残高がなくても直接買える」導線を明示する（ロケール `purchase_without_balance` / `wallet_insufficient_with_purchase` / `purchase_direct_default`、インライン導線は #33 の Gold 統一に沿う）。
- 残高不足時の表示: `insufficient_balance` はチャージ導線と購入導線の両方（Gold ボタン2つ＋ `wallet_insufficient_with_purchase` 文言）。`purchase_required` は購入導線のみ（文言に `purchase_without_balance` を付記）。設定パネルの残高表示は現行どおり。
- Stripe は使わない（参照もしない）。

## 出典

- https://freemius.com/help/api/（Bearer Token Authentication / Making API Requests / Other Scopes and Authentication）
- https://api.freemius.com/v1/openapi.json（product スコープのパス形、`/checkouts` 不存在の実測）
- https://freemius.com/help/documentation/checkout/integration/hosted-checkout/（hosted URL schema、plan 必須、通貨 `usd|eur|gbp`、Verifying the Data）
- https://freemius.com/help/documentation/saas-sdk/js-sdk/checkout/（`freemius.checkout.create({ user, planId })`）
- https://freemius.com/help/documentation/marketing-automation/events-webhooks/（Validating Webhook Signatures: `x-signature` + HMAC-SHA256 + product secret key、Types of Events）
- https://freemius.com/help/documentation/saas-sdk/js-sdk/webhooks/（`x-signature` 検証、`processFetch/processNodeHttp`）
