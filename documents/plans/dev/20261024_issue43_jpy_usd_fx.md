# Issue #43 続き: 円→USD 換算（FREEMIUS_JPY_USD_RATE）実装計画書（BDD）

- 作成日: 2026-10-24
- 対象ブランチ: `feat/agent-bank`（開始 head `8d87b0cc3`、PR #45 → main オープン中。push は自動反映、新規 PR は作らない）
- オーナー決定: **決済は Freemius 一本。JPY 価格を USD に換算して請求。換算レートは環境変数 `FREEMIUS_JPY_USD_RATE`（1 JPY = 何 USD、例 `0.0067`）**。plan 優先順位は維持（`listing.freemius_plan_id` → `FREEMIUS_PLAN_MAP` → `FREEMIUS_PLAN_ID`）
- 根拠ツール: `read_file: persona_purchases_controller.rb・freemius_client.rb・freemius_production_setup.md・persona_purchases_spec.rb・freemius_client_spec.rb・dev/persona_purchases_controller.rb・ChatPanelApp.js・chat_panel_helper.rb・ja.yml/en.yml・show.haml` で現行規約確認 / `terminal: gh issue view 43` で事実確認 / `grep: Freemius|persona_purchase|TOPUP|price_cents` で横断確認
- Plan Architect レビュー（自己照合、スキル不在のため手順準拠）: `FreemiusClient` は変更しない（plan 解決の優先順位・hosted URL 組み立てを維持）。換算は `FreemiusPricing` に集約し #46 から再利用可能にする。`amount_cents`（既存 JPY）は後方互換で残す。ウォレット文言・導線は不変。フロントは React 16.1 クラスコンポーネント規約を守る

## 設計決定（可逆・仮定の記録）

- 換算式: `usd_cents = ceil(JPY円 × rate × 100)`（BigDecimal、最小通貨単位 cent で切り上げ）。切り上げの理由: 表示円額に対して不足徴収にしない（事業者保護）。`1 USD = 100 cents`。`listing.price_cents` は円額として扱う（JPY に補助通貨なし。spec の `price_cents: 3000, currency: "JPY"` = ¥3000 と一致）。
- 未設定時: レート欠け・不正値は「未設定」扱い。**本番は 503 `payment_unconfigured`**（既定レートでの無断課金はしない）。既存の product/Bearer/plan 欠け 503 `purchase_not_configured` は維持（別条件・別 error_type、回帰を壊さない）。dev 擬似決済はレート不要で従来通り。
- plan 乖離: 真の請求額は Dashboard の plan 価格であり、hosted checkout 画面自体が真の金額を購入者に示すため、換算表示は「目安（約）」。任意 env `FREEMIUS_PLAN_PRICE_MAP`（`{"<plan_id>": <usd_cents>}`）がある場合のみ許容差チェック（`FREEMIUS_PRICE_TOLERANCE_PCT`、既定 20）を行い、超過は警告ログ＋200継続（遮断しない。為替変動・tier 価格での誤遮断を避ける）。map 無設定時は運用目視（Dashboard 価格 × レート逆算の対応表で確認）。
- フロント遷移: 200 応答に USD 額が含まれる場合、請求額メッセージを表示して約1.2秒後に checkout へ遷移する（従来は即時遷移。金額を見せるための可逆な UX 変更）。

---

## タスク一覧（振る舞い単位）

### T1: `FreemiusPricing` に換算を集約する（#46 再利用の単一入り口）
- 振る舞い: 新規 `app/services/freemius_pricing.rb`（module、既存 `FreemiusClient` と同規約）。`rate` は `ENV["FREEMIUS_JPY_USD_RATE"]` を厳密 parse（前後空白 strip、`Float()`、finite かつ > 0 のみ有効。それ以外は nil）。`configured?` は rate 有効時のみ true。`usd_cents_for_jpy(yen_cents)` は `ceil(円 × rate × 100)` を Integer で返す。`amounts_for_jpy(yen)` は `{ amount_jpy, amount_usd_cents, currency: "usd", fx_rate }` を返す。`plan_price_map` は `FREEMIUS_PLAN_PRICE_MAP`（JSON `{plan_id: usd_cents}`、壊れていたら `{}`）。`within_tolerance?(converted, plan_price, pct)` と `check_plan_price(plan_id, converted)`（`:ok` / `:unknown` / `:mismatch`、mismatch は warn ログ）。
  - 正常系: rate `0.0067`、3000円 → 2010 cents。100円 → 67 cents。`amounts_for_jpy(3000)` → `{ amount_jpy: 3000, amount_usd_cents: 2010, currency: "usd", fx_rate: 0.0067 }`。
  - 異常系: 未設定・空・`abc`・`0`・負・`NaN`・`Infinity` → `rate == nil`、`configured? == false`、`usd_cents_for_jpy` は `RateMissingError`（`ApiError` 系）を送出（呼び出し側が 503 に変換）。既定レートでの黙認課金はしない。
  - エッジ: 0円 → 0（切り上げの例外）。1円 × 0.0067 = 0.67 → 1。端数（rate `0.00673` × 100円 = 67.3）→ 68。巨大額（9,999,999円 × 0.0067 = $66,999.9933）→ 6700000。負数 → 0 に丸める（500 にしない）。float 誤差（`0.29*100` 問題）は BigDecimal で回避する例を spec に含める。map に plan が無い → `:unknown`（チェックなし）。
- 検証: 新規 `spec/services/freemius_pricing_spec.rb`。既存 `freemius_client_spec.rb` は変更しない。

### T2: 購入 API に換算を組み込む（503 分岐＋返却値追加）
- 振る舞い: `POST /api/v1/persona_purchases` は plan 解決後に `FreemiusPricing.configured?` を確認する。未設定 → 購入権利を作らず 503 `{ error, error_type: "payment_unconfigured", reason: "fx_rate_unconfigured" }`（`build_hosted_checkout_url` は呼ばない）。設定済み → 200 に既存 field（`checkout_url/listing_id/plan_id/amount_cents/provider`）＋ `amount_jpy/amount_usd_cents/currency/fx_rate` を返す。plan 価格 map 照合で乖離 → warn ログ＋200継続。`already_purchased`・401/404/422/502 の既存分岐は不変。client の金額・通貨指定は従来通り無視。
  - 正常系: rate `0.0067`、listing 3000円、plan `5678` → 200、`amount_jpy: 3000`、`amount_usd_cents: 2010`、`currency: "usd"`、`fx_rate: 0.0067`、`checkout_url` は `/product/1234/plan/5678/` を含む。
  - 異常系: レート欠け → 503 `payment_unconfigured`（`purchase_not_configured` とは別 type。既存 503 例は維持）。plan 欠け → 従来通り 503 `purchase_not_configured`。
  - エッジ: 無料（0円）は従来通り 422 のため換算しない。`fx_rate` は Float のまま返す（文字列化しない）。
- 検証: `spec/requests/api/v1/persona_purchases_spec.rb` を更新（`FreemiusPricing` の stub を追加、既存例の回帰維持＋新規例: 換算 field・503 `payment_unconfigured`・乖離 warn でも 200）。

### T3: フロントに USD 請求額の表示を追加する（ウォレット文言は不変）
- 振る舞い: `ChatPanelApp.js handlePurchase` は (a) 503 `payment_unconfigured` → 新規文言 `purchase_payment_unconfigured` を表示、(b) 200 で `amount_usd_cents` あり → 新規文言 `purchase_usd_charge`（`¥{jpy}（約 ${usd} USDで請求）`）を表示して約1.2秒後に `checkout_url` へ遷移、(c) 既存の `purchase_not_configured`/`already_purchased`/`checkout_failed` 挙動は維持。`DEFAULT_I18N`・`tFormat` で欠けキーの blank を防ぐ。新規キーのみ追加し既存 wallet 文言は一切変更しない。出品ページ（`show.haml` 価格ボックス）にレート設定時のみ USD 目安行（`lamprey.listings.usd_billing_note`）を追加する。
  - 正常系: 例 3000円・2010cents → メッセージ「¥3,000（約 $20.10 USDで請求されます）」→ checkout へ遷移。
  - 異常系: レート未設定 → 「決済設定が不足…」表示で遷移しない。i18n 未供給でも既定文言で表示される。
  - エッジ: 旧応答（換算 field なし、キャッシュ等）→ 従来通り即時遷移に劣化（`wallet_redirecting`）。
- 検証: `cd client && npx webpack --mode=development --config webpack.client.config.js` 成功。生成物はコミットしない。

### T4: ロケール・helper を追加する（既存キー不変）
- 振る舞い: `config/locales/ja.yml`・`en.yml` の `lamprey.chat` に `purchase_usd_charge`・`purchase_payment_unconfigured` を追加、`lamprey.listings` に `usd_billing_note` を追加する。`app/helpers/chat_panel_helper.rb` の i18n allowlist に chat の2キーを追加する。既存 wallet/purchase キーの文言変更はしない。
  - 正常系: ja/en ともにプレースホルダ（`%{jpy} %{usd}`）が解決される。
  - エッジ: helper 未追加のキーはフロントに届かないため、追加漏れは spec/目視で検出する。
- 検証: `grep` でキー存在確認、chat panel の i18n props に含まれることを確認。

### T5: 文書を追記する（値の記載なし）
- 振る舞い: `documents/guides/freemius_production_setup.md` に対応表（`FREEMIUS_JPY_USD_RATE`・`FREEMIUS_PLAN_PRICE_MAP`・`FREEMIUS_PRICE_TOLERANCE_PCT`）＋換算式・丸め・未設定時挙動・plan 対応方法（単一/複数時の Dashboard 価格 × レート逆算の目安式）・乖離時の扱い（warn 継続）を追記する。`.env` への追記はしない。値は書かない。
- 検証: キー名の grep 一致、秘密値が含まれないこと。

### T6: 検証・記録・報告する
- 振る舞い: `bundle exec rspec spec/services/freemius_pricing_spec.rb spec/services/freemius_client_spec.rb spec/requests/api/v1/persona_purchases_spec.rb`（対象指定のみ。全体緑は主張しない）。`bundle exec rubocop` を変更ファイルに実行。webpack ビルド確認。実際のカード決済は行わない。完了後に commit＋push（`feat/agent-bank` のみ、PR #45 に自動反映）、Issue #43 に換算方式＋実測値をコメントし、最終報告する。
  - 禁止: `main` への push/マージ、本番 DB・秘密値・実決済、Stripe 再導入、プライマリ checkout 変更、新規 PR、既定レート無断課金。
