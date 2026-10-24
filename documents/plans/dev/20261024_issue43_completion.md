# Issue #43 完成（Freemius 一本）実装計画書（BDD）

- 作成日: 2026-10-24
- 対象: `routeflags/agent-bank` `feat/agent-bank`（開始 head `306c968fc`、PR #47 へ push）
- オーナー方針: **Stripe は使わない。Freemius のみ。** 対象は #43 本体＋#46・#48 のコード側
- 根拠ツール: `read_file: freemius_client.rb・freemius_pricing.rb・freemius_topup_plans.rb・persona_purchases_controller.rb・wallet_topup_controller.rb・freemius_webhooks_controller.rb` で現行規約確認 / `fetch: freemius.com/help/documentation/marketing-automation/events-webhooks/・checkout/integration/hosted-checkout/` で公式仕様確認 / `grep: success_url|cancel_url|freemius` で未配線確認 / `terminal: git fetch・gh issue view 43/46/48` で同期・受け入れ条件確認
- 確定事実（再調査不要）: Checkout はホスト型・plan 単位、任意額 API なし、通貨 USD/EUR/GBP のみ / 円→USD は `FreemiusPricing`（`FREEMIUS_JPY_USD_RATE`）で fail closed / 署名は `x-signature=HMAC-SHA256(raw body, PRODUCT_SECRET_KEY)` / サーバー API は product スコープで疎通（`GET /v1/products/41567.json`→200、plans 2 件、`default_plan_id=74358`）/ plan `74358 credit_topup`（`PLAN_ONETIME_ID` 共用）、`74360 starter`（未配線）/ 購入 E2E は Checkout 画面到達まで確認 / `FREEMIUS_TOPUP_PLAN_MAP` は未設定（#48 判断待ち、勝手に決めない）

## T1: webhook 付与条件の変更（署名正＋API 補助）

- 振る舞い: `POST /webhooks/freemius` は署名検証（`PRODUCT_SECRET_KEY` の HMAC）が正のとき処理する。`payment.created` の persona/wallet 両経路で `FreemiusClient.get_payment` の成否を付与条件から外す。API 取得成功時は従来どおり厳密照合する（`status` があれば completed 系のみ通過、無ければ通過。`gross`→cents が 0 以下は停止。固定額は map 額との乖離を warn）。API が `ApiError`（401/404/5xx/timeout/接続失敗）で失敗したときは警告ログ `Payment <id> verification unavailable (<msg>), granting by signature` を残し付与を継続する。金額検証が必要な箇所（wallet の legacy gross 加算）は API 成功時のみ厳密照合し、API 失敗＋map 額なしの legacy は金額確定不能のため 200 skip（金額を発明しない）。
  - 正常系: 署名正＋`payment.created { payment: { id: fs_pay_p1, gross: 30.0, metadata: { type: persona_purchase, user_id, listing_id } } }`＋API 200 → 購入権利 1 件＋初期トークン付与、`payment_reference: freemius:<id>`。署名正＋固定額 `plan_id: 5678`＋API 200 → map 額を加算。
  - 異常系: 署名不正/欠け→401 で何もしない。`payment id` 欠け・`listing/person/wallet` 不明→200 skip（500 にしない）。API が `status: pending` 等の非 completed を affirmative に返したとき→200 skip（付与しない）。API が `ApiError` のとき→warn して付与継続（persona は entitlement、固定額 wallet は map 額）。legacy wallet（plan なし）で API 失敗→金額不明のため 200 skip。
  - エッジ: 実在しない payment id＋署名正＋API 404/`ApiError`→persona/固定額は付与継続（「決済済みなのに付与されない」経路を残さないことの証明に使う）。`fs_pay_1` と `fs_pay_10` の混同なし（`Wallet#topup!`＋`find_exact_topup_transaction` の厳密一致維持）。二重配送は二重付与しない（persona は `create_for` の active 重複＋初期トークン冪等、wallet は `freemius:<id>` 厳密一致）。
- 実装: `app/controllers/freemius_webhooks_controller.rb` の `verify_payment_completed` を `verify_payment_auxiliary`（成功時 `{ amount_cents }`、affirmative 不正時 `nil + reason`、API 失敗時 `:unavailable`）に分離し、`handle_persona_purchase_completed`・`handle_wallet_topup_completed` で分岐。spec は署名正＋API 失敗でも付与する例を追加し、既存の pending 停止例は維持。
- 検証: `spec/requests/freemius_webhooks_spec.rb` に対象指定実行＋isolated 再実行。設計判断は Issue #43 に記録。

## T2: 返金・サブスクの実仕様突き合わせ

- 振る舞い: 受理イベントは実名 `payment.created` / `payment.refund` / `subscription.created` / `subscription.cancelled` / `subscription.renewal.failed` を正とし、旧名 `payment.completed` / `payment.refunded` は後方互換で受理する。`subscription.renewed` / `subscription.expired` は実在しないため legacy 扱い（受理は維持、文書で明記）。`subscription.canceled`（米綴り）も受理する。`payment.dispute.*` 等の未知イベントは 200 ignore＋info ログ。`payment.refund` は元 topup の厳密一致があるときのみ `Wallet#refund!`（冪等、二重 reverse なし）。未知 payment の refund は warn して 200。サブスクは `freemius_subscription_id` 優先＋初回 `subscription.created` のみ metadata の person/listing から紐付け、`current_state` の state machine で遷移（`expired`→`canceled` 扱い維持）。
  - 正常系: `payment.refund { payment: { id: fs_pay_9 } }`→refund 1 件＋残高減。二重配送は不変。`subscription.cancelled`→`canceled`、`renewal.failed`→`past_due`。
  - 異常系: 署名不正→401。対象不明→200 skip。
  - エッジ: `event: { type }` と文字列の両対応維持。`canceled/cancelled` 両綴り受理。
- 実装: `freemius_webhooks_controller.rb` の `SUBSCRIPTION_EVENTS` に `subscription.canceled` を追加し、コメントを実名/legacy 分離に更新。payload 参照（`objects.subscription.id`）は維持。
- 検証: 既存 webhook spec の subscription 例＋新規 `canceled` 綴り例。

## T3: success/cancel 戻り先の実装（ロケール文言付き）

- 振る舞い: Freemius hosted Checkout の仕様に沿う。`cancel_url` は per-checkout の query（back ボタンが使う）のためサーバーが毎回付与する。persona 購入は出品詳細 URL、wallet 固定額はサイト基点 URL を `cancel_url` として `build_hosted_checkout_url` に渡す。`success redirect` は Dashboard の Plans→Customization→`Redirect Checkout to a custom URL` の global 設定のため per-checkout では送らず、代わりに戻り先エンドポイント `GET /freemius/return` を実装する。Freemius は成功時に `user_id/plan_id/email/payment_id/license_id/amount/signature` 等を query 付与する。`signature` は `HMAC-SHA256(clean_url, PRODUCT_SECRET_KEY)`（`&signature=...` 除去後の絶対 URL）で検証する。検証正→購入完了表示（listing 解決時は出品へのリンク付き、解決不能時は汎用完了表示）。検証不正→警告表示＋ログ（500 にしない）。文言は `ja.yml`/`en.yml` の `freemius_return.*` のみ。
  - 正常系: `POST /api/v1/persona_purchases { listing_id: 23 }`→200 の `checkout_url` に `cancel_url=<出品詳細>` を含む。`GET /freemius/return?payment_id=..&plan_id=74358&signature=<正>`→200 完了表示。`cancel_url` 追跡→出品詳細 200。
  - 異常系: 署名不正の return→200 で警告表示（500 にしない）。未設定（product/Bearer/plan/レート）→従来どおり 503。
  - エッジ: 単一 plan 運用では `plan_id` だけでは listing 特定不能のため汎用完了表示に留める（誤った出品への誘導をしない）。`listing_id` の推測表示はしない。return URL 自体が redirect すると署名検証が壊れるため redirect しない（直接 render）。
- 実装: 新規 `app/controllers/freemius_return_controller.rb`＋`app/views/freemius_return/success.html.erb`＋routes（locale 外 `get /freemius/return`）。既存 2 コントローラで `cancel_url` を生成して渡す。`FreemiusClient.build_hosted_checkout_url` は変更なし（`cancel_url/extra` 対応済み）。`ja.yml`/`en.yml` に `freemius_return.success_title/success_body/pending_note/back_to_listing/back_to_top/invalid_signature` を追加。フロント変更はなし（203 行 ChatPanel の遷移先が `cancel_url` 付き URL になるのみ）。
- 検証: request spec 新規（`spec/requests/freemius_return_spec.rb`）＋既存 persona/wallet spec の `cancel_url` 含有確認。`bundle exec rubocop` 0。フロント変更なしのため webpack 不要。

## T4: 冪等性の維持

- 振る舞い: 同一 `payment_id` の二重配送で二重付与・二重加算しない。`fs_pay_1` と `fs_pay_10` を混同しない。persona は `create_for` の同一 person+listing active 重複＋`Wallet#topup!` の `freemius:<id>` 厳密一致。wallet は `freemius:<payment_id>` の JSON exact。refund は `refund!` の冪等。いずれも LIKE は prefilter のみで最終判定は JSON parse exact。
  - 正常系: 同一 payload 2 回→残高・件数不変で 200。
  - エッジ: `fs_pay_1` 処理後に `fs_pay_10` が別件として処理される。メール照合は exact（`Person.by_email` の `WHERE address = ?`・lowercase）。
- 実装: 既存維持（変更なし）。T1 の fail-open 化後も冪等ガードは先に評価する（grant 前に duplicate check）。
- 検証: 既存 webhook spec の冪等・exact 例を維持＋T1 新規例でも二重送付不変を確認。

## T5: persona/wallet 決済経路の総点検修正（T1–T4 以外）

- 振る舞い: `FreemiusTopupPlans.persona_plan_ids` の重複検出に `PLAN_ONETIME_ID`・`PLAN_MONTHLY_ID` を含める（現行は `FREEMIUS_PLAN_MAP`/`FREEMIUS_PLAN_ID` のみで単一既定 plan との重複を見逃す）。`FREEMIUS_TOPUP_PLAN_MAP` の値は決めない（未設定のまま 503 fail-closed を維持）。`FreemiusClient` の product スコープ・Bearer・`gross`→cents・`configured?` は変更なし。`FreemiusPricing` の fail-closed・切り上げ・tolerance warn-only は変更なし。
  - 正常系: `FREEMIUS_TOPUP_PLAN_MAP={"74358":1000}`＋`PLAN_ONETIME_ID=74358`→`validation_errors` に overlap。
  - 異常系: 従来どおり未設定時は wallet 固定額 503。
- 実装: `app/[REDACTED]/freemius_topup_plans.rb` の `persona_plan_ids` 拡張＋spec 追加。
- 検証: `spec/[REDACTED]/freemius_topup_plans_spec.rb` 対象実行。

## T6: 実サーバー検証（カード決済なし）

- 振る舞い: Rails を 3000 以外（3010 等）で起動し、ログイン→`POST /api/v1/persona_purchases`→`checkout_url` 追跡で 200 を確認する。署名付き webhook（`PRODUCT_SECRET_KEY` で自作署名）を実 HTTP で投げ、購入権利付与・残高加算・冪等を確認する。実在しない payment id＋署名正の場合は付与継続（warn）になることを確認し、「決済済みなのに付与されない」経路が残っていないことを示す。管理画面・既存決済 spec への影響を確認する。
  - 正常系: persona checkout 200＋Checkout ページ 200。webhook persona→`UserPlanSubscription`＋1・初期トークン付与。wallet 固定額（`FREEMIUS_TOPUP_PLAN_MAP` を検証用に一時設定した場合は検証後に未設定へ戻す。恒久値は決めない）→map 額加算。同一 payload 再送→不変。
  - 異常系: 署名不正→401。実在しない id＋署名正→warn 付き付与継続（T1 の意図どおり）。
- 検証: `bundle exec rspec` は対象指定＋isolated 再実行＋変更前後の失敗集合比較（全体緑を主張しない）。`bundle exec rubocop` 変更ファイル 0。生成物コミットなし。

## T7: 文書化（`documents/guides/freemius_production_setup.md` 最終化）

- 振る舞い: 環境変数一覧（用途・参照元・未配線の明示）、本番投入手順（Dashboard 設定→Secrets→Webhook Listener 登録→疎通確認）、実カード決済でしか確認できない項目のチェックリスト（オーナーが 1 回流せば終わる形）、既知の制約（plan 単位・通貨 USD・レート固定運用）を最終状態に更新する。秘密値は書かない。
- 検証: 文書の存在＋キー名 grep 一致（値なし）。

## 実装しないこと

- 実カード決済（カード情報を扱わない）。Stripe の再導入。`FREEMIUS_TOPUP_PLAN_MAP` の値決め（#48 判断待ち）。`main` への push/マージ・本番 DB アクセス・新規 PR 作成・プライマリ checkout の変更。Sharetribe コア Stripe（`PaymentSettings` 等）の広範削除。JPY 建て課金。埋め込み Checkout（`PRODUCT_PUBLIC_KEY` は保持のみ）。
