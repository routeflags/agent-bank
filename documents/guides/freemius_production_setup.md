# Freemius 本番決済 環境変数対応表・運用手順（Issue #43・#51）

- 対象: `routeflags/agent-bank`（Lamprey / 楽市楽問）、ブランチ `feat/agent-bank`
- 方針: **Freemius 一本。Stripe は使わない**（オーナー決定）
- 方針（Issue #51）: **課金はウォレット残高（チャージ）のみ。ペルソナ単体の「購入」概念は持たない。** チャージは Freemius の固定額 plan（`credit_topup` 74358 単独）で行う。チャット開始の条件は残高のみ。
- 前提: Checkout はホスト型・plan 単位。任意金額の Checkout 作成 API は存在しない（詳細は Issue #43 コメント `6382342198`）。

## 1. 対応表（どれが何に使われるか）

| 環境変数 | 用途 | 参照元 | 備考 |
|---|---|---|---|
| `PRODUCT_ID` | Freemius product_id（数値）。サーバー API のパス `GET /products/{product_id}/...` と hosted checkout URL `.../product/{product_id}/plan/...` に使用。旧名 `FREEMIUS_PRODUCT_ID` も後方互換で読む | Dashboard product Settings → API & Keys の product ID | 設定済み（`.env`）。値はコミット・報告に書かない |
| `API_BEARER_AUTHORIZATION_TOKEN` | サーバー API の Bearer トークン（`Authorization: Bearer`）。`get_payment` / `get_subscription` の認証に使用 | Dashboard product Settings → API & Keys → API Bearer Authorization Token | 32 文字。`.env` に設定済み。旧名 `FREEMIUS_API_KEY` も後方互換で読むが、新規は本キーを使うこと |
| `PRODUCT_SECRET_KEY` | Webhook `x-signature`（HMAC-SHA256(raw_body, secret)）と success redirect `signature`（HMAC-SHA256(clean_url, secret)）の検証鍵 | Dashboard product Settings → API & Keys → Secret Key | 32 文字。`.env` に設定済み。旧名 `FREEMIUS_WEBHOOK_SECRET` も後方互換で読むが、新規は本キーを使うこと。公開・コミット厳禁 |
| `PRODUCT_PUBLIC_KEY` | フロント公開鍵（Buy Button / checkout.js の公開側）。現行のホスト型リダイレクトのみの運用ではサーバーは使わない。将来の埋め込み Checkout 用に保持 | Dashboard product Settings → API & Keys → Public Key | 32 文字。`.env` に設定済み |
| `PLAN_MONTHLY_ID` | 月次 plan_id。**現行コードでは課金に未使用** | Dashboard Plans の monthly plan ID | `.env` に設定済み。月次課金の導線を入れる場合は別 Issue で配線する |
| `STORE_ID` / `STORE_PUBLIC_KEY` / `STORE_SECRET_KEY` | Freemius **store** スコープの識別子と鍵。`GET /v1/stores/{id}.json?public_key=...` は 200 で返ることを実測確認済み。**現行の product スコープ実装では未使用** | Store Settings → API & Keys | 将来 store 単位の集計・商品一覧を扱う場合に使う。値はコミット・報告に書かない |

> **Issue #51 で廃止**: `PLAN_ONETIME_ID` / `FREEMIUS_PLAN_ID` / `FREEMIUS_PLAN_MAP`（ペルソナ購入用の plan 解決）はコードから削除済み。`.env` に残っていても読みに行かない。整理時に削除してよい。
| `FREEMIUS_API_BASE_URL` | サーバー API 基底 URL（既定 `https://api.freemius.com/v1`）。テストのスタブ用 | 既定値で可 | 旧 `FreemiusClient` の `/v1/checkouts` 前提は廃止済み |
| `FREEMIUS_JPY_USD_RATE` | JPY→USD 換算レート（1 JPY = 何 USD か。例 `0.0067`）。`FreemiusPricing` が読み、wallet チャージ額の換算と USD 目安表示に使用 | オーナーが投入（値はコミット・報告に書かない） | **未設定・不正値時は本番課金を 503 `payment_unconfigured` で拒否**。既定レートでの黙認課金はしない。dev 擬似決済はレート不要 |
| `FREEMIUS_PLAN_PRICE_MAP`（任意） | plan 価格の対応表（JSON。例 `{"5678":1999}` = plan 5678 は 1999 USD cents）。換算値との乖離チェックに使用 | 価格帯が複数ある場合に運用で管理 | 未設定時はチェックなし（`:unknown`）。壊れた JSON も `{}` 扱い |
| `FREEMIUS_TOPUP_PLAN_MAP` | 固定額チャージの額面対応表（JSON）。`GET status` の額面一覧・`POST` の plan 解決・webhook の付与額の唯一の正。**現行運用は `credit_topup`（plan 74358）単独** | Dashboard の plan_id と付与円額を対応付けて投入。付与額は plan 実価格（USD）に対する逆ザヤが出ない値をオーナーが決定する | 未設定・空・壊れた JSON・空オブジェクト・不正値（非正整数・100〜100,000円範囲外）・重複キーはすべて「未設定」扱いで本番チャージは 503。値はコミット・報告に書かない |
| `FREEMIUS_PRICE_TOLERANCE_PCT`（任意） | 乖離チェックの許容差（%、既定 `20`） | 既定で可 | 数値以外は既定値にフォールバック |
| `FREEMIUS_API_KEY`（旧） | `API_BEARER_AUTHORIZATION_TOKEN` の旧名。後方互換で読むのみ | — | 新規設定は `API_BEARER_AUTHORIZATION_TOKEN` を使うこと |
| `FREEMIUS_WEBHOOK_SECRET`（旧） | `PRODUCT_SECRET_KEY` の旧名。後方互換で読むのみ | — | 新規設定は `PRODUCT_SECRET_KEY` を使うこと |

`FreemiusClient` の env 名は新キーに寄せている。旧キーは `configured?` / `webhook_secret` / `bearer_token` のフォールバックとしてのみ読む。

## 2. Dashboard 側の設定手順（コード変更なしで運用がすること）

1. Developer Dashboard で product を確認し、`PRODUCT_ID`・`API_BEARER_AUTHORIZATION_TOKEN`・`PRODUCT_SECRET_KEY`・`PRODUCT_PUBLIC_KEY` を取得して本番 Secrets に投入する。
2. Plans/Pricing でチャージ用の固定額 plan を確認する（価格・通貨 `USD` 前提。Freemius 通貨は `USD/EUR/GBP` のみで `JPY` 建て不可）。**現行運用は `credit_topup`（plan 74358）単独。persona 購入用の plan は作らない**（Issue #51）。
3. `.env`（本番 Secrets）に `FREEMIUS_TOPUP_PLAN_MAP` を 1 行で投入する（例: チャージ plan 1 本の場合）。付与額（円）は plan 実価格（USD）に対する逆ザヤが出ない値をオーナーが決定する（Issue #53）。**値自体はコミット・Issue 記載とも禁止。投入手順のみをここに残す。**
4. Webhooks Listener を作成し、URL `https://<本番ドメイン>/webhooks/freemius` を登録する。対象イベントは少なくとも `payment.created`・`payment.refund`・`subscription.created`・`subscription.cancelled`・`subscription.renewal.failed` を含める（コードは `subscription.canceled` 綴り・旧名 `payment.completed` / `payment.refunded` も後方互換で受理する）。署名方式は既定（`x-signature`）でよい。
5. Plans → Customization で success redirect（Redirect Checkout to a custom URL）に `https://<本番ドメイン>/freemius/return?lang=ja` を設定する（日本語表示。英語の場合は `?lang=en` 又は無指定）。成功時は `user_id`・`plan_id`・`email`・`payment_id`・`license_id`・`amount`・`signature` 等が query に付与され、アプリは `signature`（`HMAC-SHA256(signature 除去後の絶対 URL, PRODUCT_SECRET_KEY)`）を検証してチャージ完了画面（汎用表示）を出す。**この URL 自体が redirect すると署名検証が壊れるため、他の URL への転送は設定しないこと**（Freemius 公式の警告）。`cancel_url`（Checkout の戻るボタン）はサーバーが checkout ごとに自動付与する（wallet はサイト基点）のため Dashboard 設定は不要。
6. 実際のカード決済は行わず、checkout リンク生成（`POST /api/v1/wallet_topup` に `plan_id` → `checkout_url`）と Dashboard の Events 一覧、サーバー API 到達性（`GET /products/{id}/payments/{id}.json`）までを確認する。

## 3. 未設定時の挙動（回帰維持・#51 更新）

- `POST /api/v1/persona_purchases` は廃止（Issue #51。404 になる）。ペルソナ購入の plan 解決・503 `purchase_not_configured` は存在しない。
- 換算レート（`FREEMIUS_JPY_USD_RATE`）欠け・不正値 → `POST /api/v1/wallet_topup` は 503 `payment_unconfigured`（`reason: "fx_rate_unconfigured"` 付き、checkout URL は作らない）。既定レートでの無断課金はしない。
- `POST /api/v1/wallet_topup`（#46・#51）: `plan_id` ありで Freemius/Bearer・レート・`FREEMIUS_TOPUP_PLAN_MAP` のいずれか欠け → 503 `payment_unconfigured`（`reason: freemius_not_configured / fx_rate_unconfigured / topup_plans_unconfigured`）。`plan_id` 不明 → 422 `invalid_plan`。`plan_id` なし（任意額 `amount_cents` 等）は非開発で 422 `plan_id_required`（任意額は受け付けない）。開発環境では `amount_cents` の擬似決済（`dev_pi_*`）が従来どおり動作する（`plan_id` 不要の経路を残す・換算レート不要）。
- `GET /api/v1/wallet_topup/status`: 固定額が使える条件（Freemius 設定済み＋レート設定済み＋TOPUP_MAP 有効）を満たすとき `topup_enabled: true, provider: "freemius", denominations: [...]`。開発は `topup_enabled: true, dev_mode: true` を維持し、固定額が使えるときは `denominations` も併せて返す。いずれも不可なら `topup_enabled: false, reason: "payment_unconfigured"`。

## 4. ウォレット任意額チャージを Freemius で実現しない理由と現行方式（#51 決定）

- 理由: Freemius に任意金額の Checkout 作成 API が存在しない（OpenAPI 全112 paths に `/checkouts` 無し、checkout 系は hosted link 組み立て・checkout token・license upgrade link のみ）。ホスト型・JS SDK とも `planId` 必須で `amount` 指定不可。通貨も `usd|eur|gbp` のみ。よって `amount_cents` 自由指定のチャージは正規フローで実現不可。無理に作らず Freemius 分岐を外している。
- 現行方式（Issue #51・オーナー決定）: **固定額チャージ plan 方式のみ**。Dashboard の額面 plan に対応する hosted URL へ遷移し、webhook `payment.created` で `FREEMIUS_TOPUP_PLAN_MAP` の付与額をチャージする。ペルソナ購入への集約案は不採用（購入概念自体を撤去）。
- Stripe へはフォールバックしない（オーナー方針）。

## 5. Stripe 除去の判断記録

- ペルソナ購入・ウォレットの経路から Stripe を外した（`create_payment_intent` / `confirm` の Stripe 分岐 / `stripe_key_configured?` / `configure_stripe_api!` を削除）。理由: オーナー方針（Freemius 一本）と、Freemius MoR 前提ではカード情報を自前で扱わないため。
- 広範な削除はしていない: Sharetribe コアの Stripe 連携（`PaymentSettings`・admin 画面・旧取引フロー・`stripe_service`・`Wallet#auto_recharge!` の Stripe 呼び出し等）は影響が大きいため残している。今回のフロー（persona 購入・wallet topup/confirm/status）からは参照しない形に留めた。`auto_recharge!` の Stripe 直接課金は本 Issue の対象外とし、自動チャージを有効化する場合は別途 Freemius 方式（手動チャージ誘導 or 固定額 plan）の検討が必要（残件）。

## 6. 通貨・残件（オーナー判断が必要なもの）

- ~~`config/billing.yml` の既定通貨は `USD` のまま（Freemius 通貨に合わせるため）。UI の円表示との不整合（Issue #43 補足）は本 Issue では直していない。JPY 建て課金は Freemius で不可のため、価格表示・請求通貨の方針決定が必要。~~ → **決定済み（オーナー）: 円価格を USD に換算して請求する。換算レートは `FREEMIUS_JPY_USD_RATE`。** 詳細は下記 §7。`config/billing.yml` の既定通貨は `USD` のまま。
- ~~plan 設計: persona ごとの価格（`listing.price_cents`）をどの plan/pricing に対応させるか。単一 plan（`FREEMIUS_PLAN_ID`）で始めるか、価格帯ごとに plan を作り `FREEMIUS_PLAN_MAP` で管理するかを決定すること。~~ → **撤去（Issue #51）: ペルソナ購入用の plan 解決（`listing.freemius_plan_id` / `FREEMIUS_PLAN_MAP` / `FREEMIUS_PLAN_ID` / `PLAN_ONETIME_ID`）はコードから削除済み。売るのは残高（ウォレットチャージ）のみ。**
- 固定額プリペイド（ウォレット）の採否: 上記 4 の代替案 1 を採用するかどうか。 → **採用（オーナー決定・#46）。Issue #51 で直接購入 (b) は撤去し、固定額チャージ (a) のみに一本化。** 詳細は下記 §8。
- 本番キー投入手順: `PRODUCT_ID` の取得と Secrets 投入、Webhook Listener 登録、success redirect 設定、サンドボックスでの checkout 到達確認。実際のカード決済は本 Issue の検証範囲外。

## 7. JPY→USD 換算（`FREEMIUS_JPY_USD_RATE`）

- 換算の単一入り口: `FreemiusPricing`（`app/services/freemius_pricing.rb`）。#46（固定額プリペイド）もここを再利用する。
- 換算式: `usd_cents = ceil(円 × rate × 100)`（BigDecimal で計算）。`1 USD = 100 cents`。`listing.price_cents` は円額として扱う（JPY に補助通貨なし）。例: rate `0.0067` のとき 3000円 → 2010 cents（$20.10）。
- 丸め: 最小通貨単位（1 cent）で**切り上げ**。理由は表示円額に対して不足徴収にしないため。境界値: 0円 → 0、1円 × 0.0067 = 0.67 → 1、端数（100円 × 0.00673 = 67.3）→ 68、巨大額（9,999,999円）→ 6,700,000、負数 → 0。spec（`spec/services/freemius_pricing_spec.rb`）で固定。
- 未設定時の挙動: 欠け・空・非数値・0・負・NaN/Infinity はすべて「未設定」扱い。本番の wallet チャージは 503 `payment_unconfigured`（`reason: fx_rate_unconfigured`）で checkout を作らない。既定値で黙って課金しない。開発の dev 擬似決済は従来どおり（レート不要）。
- API の返却値（`POST /api/v1/wallet_topup` の 200）: `checkout_url/plan_id/credit_jpy（付与円額）/amount_usd_cents/currency: "usd"/fx_rate/provider` を返す。フロントは USD 額（目安）を表示してから checkout へ遷移する。
- plan との対応方法: Freemius plan の価格は Dashboard 側で固定 USD。換算値は「購入者にいくらと表示するか」の目安に使う。付与額（円）は `FREEMIUS_TOPUP_PLAN_MAP` の値が正で、plan 実価格（USD）に対する逆ザヤが出ないよう運用で決定する（Issue #53）。
- 乖離時の扱い: 任意 env `FREEMIUS_PLAN_PRICE_MAP`（`{"<plan_id>": <usd_cents>}`）がある場合のみ、`FREEMIUS_PRICE_TOLERANCE_PCT`（既定 20%）で照合する。超過は警告ログ（`[FreemiusPricing] plan price drift`）に留め、200 を継続して遮断しない。理由: 真の請求額は hosted checkout 画面が購入者に示すため、為替変動・tier 価格での誤遮断を避ける。map 未設定時は運用目視（Dashboard 価格 × レート逆算の対応表）で確認する。

## 8. 固定額チャージ（Issue #46・#51 オーナー決定）

- 方針: **固定額チャージのみ**。ペルソナ直接購入は Issue #51 で撤去した。チャットのトークン消費は残高から引く（現行どおり）。残高不足時の導線は「チャージする」のみ（「購入する」は出さない）。
- 額面 plan の運用: Dashboard に額面 plan を作る（**現行は `credit_topup` 1 本**）。`FREEMIUS_TOPUP_PLAN_MAP`（JSON `{ "<plan_id>": <付与クレジット(円)> }`）で plan → 付与額を解決する。これを唯一の正とし、起動時（initializer）＋参照時（`FreemiusTopupPlans.validation_errors`）に欠落・重複・不正値を検証する。
- API:
  - `GET /api/v1/wallet_topup/status` は購入可能な額面一覧（`plan_id` / `credit_jpy` / `estimated_usd_cents` / `currency: "usd"` / `fx_rate` / `plan_price_usd_cents`）を返す。換算は `FreemiusPricing` のみを使う（新しい換算ロジックは書かない）。通貨は USD 固定。円表示は換算値であり、レート変動で表示が変わることを UI（`topup_fx_note`）・文書で明示する。
  - `POST /api/v1/wallet_topup` は `plan_id` を受け取りホスト型 Checkout URL を返す。任意額 `amount_cents` は 422（`plan_id_required`）。開発の擬似決済（`amount_cents` → `dev_pi_*` → `confirm`）は従来どおり（`plan_id` 不要）。
  - webhook `payment.created`: `plan_id` → 付与クレジット（円）を `FREEMIUS_TOPUP_PLAN_MAP` から解決し `Wallet#topup!` で加算。`freemius:<payment_id>` の厳密一致で冪等（二重配送で二重加算しない・`fs_pay_1` と `fs_pay_10` の混同なし）。plan 不明は加算しない。plan なしの legacy は検証済み gross を加算（既存テスト互換）。
- ホスト型 Checkout はサーバー側で metadata を付けられないため、webhook の local ユーザー特定は次の順序で行い、取り違えが起きないことを spec で固定する: 明示 `wallet_id` → 明示 `user_id`（local id）→ `user_email` の厳密一致（`Person.by_email` の `WHERE address = ?`・lowercase exact、前方一致なし）。`objects.user.email` / `payment.user_email` / `payment.user.email` を見る。
- 残高不足時の表示: `insufficient_balance` はチャージ導線のみ（Gold ボタン1つ＋ `wallet_insufficient` 文言）。`purchase_required` は廃止（Issue #51）。設定パネルの残高表示は現行どおり。
- Stripe は使わない（参照もしない）。

## 9. Webhook 付与条件の設計（Issue #43 completion）

- 署名（`x-signature` = `HMAC-SHA256(raw body, PRODUCT_SECRET_KEY)`）を真正性の主根拠とし、サーバー API の `get_payment` 再取得は補助とする。API が一時的 (`401` / `404` / `5xx` / timeout) に失敗しても残高加算は止めず、警告ログ（`verification unavailable ... crediting by signature`）を残して付与を継続する。金額検証が必要な箇所（wallet の legacy gross 加算）は API 取得成功時のみ厳密照合し、API 失敗＋map 額なしの場合は金額確定不能のため付与しない（金額を発明しない）。API が affirmative に未完了 (`status: pending` 等・金額ゼロ) を返した場合は従来どおり付与しない。
- 理由: 決済済みにもかかわらず API の一時的失敗で残高が加算されない経路を残さないため。署名検証済みの webhook は Freemius 正規発行であり、可用性を優先する（判断記録は Issue #43 コメント参照）。
- 冪等性は維持: 同一 `payment_id` の二重配送は二重付与・二重加算しない。`fs_pay_1` と `fs_pay_10` の混同なし（`Wallet#topup!`・refund 照合の JSON exact 維持、メール照合 exact）。

## 10. 実カード決済でしか確認できない項目（オーナーが 1 回流せば終わる形）

- [ ] 実カードでチャージ用 hosted checkout（`credit_topup` plan）を最後まで流し、決済完了後に Dashboard で設定した `GET /freemius/return?lang=ja` に戻り、チャージ完了画面（署名検証正）が出ること
- [ ] `GET /api/v1/wallet_topup/status` が額面 1 件（チャージ plan のみ）を返し、`POST /api/v1/wallet_topup`（`plan_id` 指定）の Checkout が 200 で開くこと
- [ ] webhook `payment.created` で残高が加算され、二重配送で二重加算しないこと
- [ ] Freemius Dashboard の Events 一覧に `payment.created` が記録され、金額・通貨 (`USD`) が想定どおりであること
- [ ] Checkout の戻るボタン (`cancel_url`) でサイト基点に戻ること
- [ ] 返金が必要になった場合、Dashboard で返金→ `payment.refund` webhook で残高が減算されること（任意・テスト返金で可）
- [ ] 月次 plan (`starter`) を使う場合、`subscription.created` / `subscription.cancelled` / `subscription.renewal.failed` の同期が動くこと（現行コードは受信のみ実装、課金導線は未配線）

## 11. 既知の制約

- Checkout はホスト型・plan 単位。サーバー API に任意額 Checkout 作成は無い。通貨は `USD/EUR/GBP` のみ（`JPY` 建て不可）。
- 円→USD 換算は `FREEMIUS_JPY_USD_RATE` の固定レート運用。未設定・不正値時は本番課金を `503 payment_unconfigured` で拒否する（既定レートでの黙認課金なし）。為替変動時のレート見直しは運用手作業。
- success 戻り先は汎用完了表示（チャージは出品に紐付かないため出品リンクは出さない）。
- `FREEMIUS_TOPUP_PLAN_MAP` の投入はオーナー作業（`.env` の 1 行。値はコミット・報告に書かない）。未設定の間、wallet 固定額チャージは `503` のまま。
- `STORE_ID` / `STORE_PUBLIC_KEY` / `STORE_SECRET_KEY` / `PRODUCT_PUBLIC_KEY` / `PLAN_MONTHLY_ID`（課金用途）は現行フローで未使用（将来用に保持）。

## 12. ローカルで webhook を受け取る（cloudflared / ngrok）

Freemius から `127.0.0.1` へは到達できないため、トンネルで公開して検証する。**実測済みの手順**:

```bash
# 1) トンネルを張って公開 URL を得る（cloudflared は brew で導入済み）
cloudflared tunnel --url http://127.0.0.1:3000 --no-autoupdate
#   → https://<random>.trycloudflare.com が出力される

# 2) Rails は未知の Host を 403 で拒否するため、トンネルのホストを許可して起動する
RAILS_DEVELOPMENT_HOSTS=<random>.trycloudflare.com bin/rails server -b 127.0.0.1 -p 3000

# 3) 経路と署名検証の確認（付与は起きない。401 が正解）
curl -i -X POST https://<random>.trycloudflare.com/webhooks/freemius \
  -H 'Content-Type: application/json' -H 'x-signature: deadbeef' -d '{}'
#   → 401 {"error":"Unauthorized"}
```

- `RAILS_DEVELOPMENT_HOSTS` を忘れると、Rails の Host Authorization が **403（HTML）** を返す。アプリの不具合に見えるので注意。
- 署名付き webhook を投げる場合は raw body をそのまま署名する（HMAC-SHA256(raw_body, `PRODUCT_SECRET_KEY`)）。
- 実測（2026-10-24・公開 URL 経由）: 署名不正 → 401 / 署名正（未知 payment id → API 404）→ 200 で購入権利 1 件 / 同一 payload 再送 → 200 で件数不変（冪等）。
- トンネル URL は一時的。検証後はプロセスを止める（公開状態を残さない）。

## 出典

- https://freemius.com/help/api/（Bearer Token Authentication / Making API Requests / Other Scopes and Authentication）
- https://api.freemius.com/v1/openapi.json（product スコープのパス形、`/checkouts` 不存在の実測）
- https://freemius.com/help/documentation/checkout/integration/hosted-checkout/（hosted URL schema、plan 必須、通貨 `usd|eur|gbp`、Verifying the Data）
- https://freemius.com/help/documentation/saas-sdk/js-sdk/checkout/（`freemius.checkout.create({ user, planId })`）
- https://freemius.com/help/documentation/marketing-automation/events-webhooks/（Validating Webhook Signatures: `x-signature` + HMAC-SHA256 + product secret key、Types of Events）
- https://freemius.com/help/documentation/saas-sdk/js-sdk/webhooks/（`x-signature` 検証、`processFetch/processNodeHttp`）
