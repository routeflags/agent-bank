# Issue #46 固定額プリペイド＋直接購入 両立 実装計画書（BDD）

- 作成日: 2026-10-24
- 対象: `routeflags/agent-bank` `feat/agent-bank`（head `e6a92f573`）
- オーナー決定: **(a) 固定額プリペイドと (b) ペルソナ直接購入の両方を実装**
- 根拠ツール: `read_file: freemius_pricing.rb / freemius_client.rb / freemius_webhooks_controller.rb / wallet_topup_controller.rb / persona_purchases_controller.rb / wallet.rb / ChatPanelApp.js / ja.yml` で現行規約確認 / `grep: by_email / topup_enabled / wallet_insufficient` で再利用点確認 / `terminal: gh issue view 46` で受け入れ条件取得
- 制約: React 16.1.1 クラス方式 / 文言は `ja.yml`・`en.yml` / Stripe 不使用 / `FreemiusPricing` のみ換算 / dev `dev_pi_*` 維持 / 新 migration 時は `structure.sql` 同時更新（今回は migration なし）

## 単位1: 固定額プリペイド基盤（`FREEMIUS_TOPUP_PLAN_MAP`）

- 振る舞い: `{"123":"付与円"}` の JSON を読み、欠落・壊れた JSON・非オブジェクト・空・空白 plan_id・非正整数・100〜100,000円範囲外・生テキスト重複キー・persona plan 重複（`FREEMIUS_PLAN_MAP` 値 / `FREEMIUS_PLAN_ID`）を `validation_errors` で返す。`configured?` が false の間は本番チャージを 503 で止める。`credit_for_plan` は厳密一致のみ（`1` と `10` の混同なし）。`available_denominations` は `FreemiusPricing` 経由の USD 目安付きでソート返却。レート未設定時は `[]`。
  - 正常系: `{"5678":1000,"5679":3000}` + rate `0.0067` → `configured? true`、`5678→1000`、`denominations [5678(670c),5679(2010c)]`。
  - 異常系: 未設定・壊れた JSON・空・不正値・重複・persona 重複 → `configured? false` + 理由。
  - エッジ: 数値文字列 `"3000"` は受理、少数・負・0・範囲外は拒否。重複は `JSON.parse` が末勝するため生テキスト走査で検出。
- 実装: 新規 `app/services/freemius_topup_plans.rb` + `config/initializers/freemius_topup_plans.rb`（起動時ログのみ、raise しない）。`FreemiusPricing` に換算追加なし。
- 検証: 新規 `spec/services/freemius_topup_plans_spec.rb`（上記全分岐）+ 既存 `freemius_pricing_spec` 回帰。

## 単位2: ウォレット API（status / create）

- 振る舞い:
  - `GET status`: 固定額可（Freemius 設定＋レート設定＋MAP 有効）→ `topup_enabled true, provider freemius, denominations[], fx_rate`。dev → `topup_enabled true, dev_mode true`（固定額可なら `denominations` 併載）。不可 → `topup_enabled false, reason payment_unconfigured`。既存 `topup_enabled/provider/reason` 互換維持。
  - `POST`: `plan_id` あり → 固定額経路（不明 `invalid_plan` 422 / 未設定 503 `freemius_not_configured|fx_rate_unconfigured|topup_plans_unconfigured` / 成功 200 `checkout_url/plan_id/credit_jpy/amount_cents/amount_usd_cents/currency/fx_rate/provider`）。`amount_cents` は無視（サーバー決定）。`plan_id` なし → dev のみ legacy `amount_cents→dev_pi_*`、非 dev は 422 `plan_id_required`（任意額拒否）。`confirm` は dev のみ維持。
  - 正常系: `plan 5678` → checkout URL `/product/1234/plan/5678/` + `credit_jpy 1000` + `usd 670c`。dev `amount 3000` → `dev_pi_*` → `confirm` で加算・二重冪等。
  - 異常系: 未知 plan 422 / レート欠け 503 / 未認証 401 / 不正 dev intent 422・403。
  - エッジ: dev＋plan 両立時は plan 優先。`user_email` 取得失敗でも checkout 継続（nil 許容）。
- 実装: `app/controllers/api/v1/wallet_topup_controller.rb` 改修。
- 検証: `spec/requests/api/v1/wallet_topup_spec.rb` 更新（非 dev 任意額 503→422、固定額 200/422/503、status 額面、dev 冪等維持）。

## 単位3: webhook（plan 解決＋ユーザー特定＋冪等）

- 振る舞い:
  - `payment.created` の dispatch は persona 優先維持（`type persona_purchase` or `plan_id→listing`）。それ以外が wallet へ。
  - wallet: `plan_id` あり → `TOPUP_MAP` の円額を加算（検証済み gross は存在確認＋drift 警告のみ、webhook body 額は信用しない）。`plan_id` 不明 → 加算せず skip。`plan_id` なし legacy → 検証済み gross 加算（既存テスト互換）。
  - ユーザー特定: 明示 `wallet_id` → 明示 `user_id` → `user_email` 厳密一致（`Person.by_email` の `WHERE address = ?`・lowercase exact。前方一致なし）。参照源は `objects.user.email / payment.user_email / payment.user.email`。取り違え防止を spec で固定。
  - 冪等: `Wallet#topup! (freemius:<payment_id>)` の厳密 JSON 一致（`fs_pay_1` と `fs_pay_10` 混同なし）。返金照合も LIKE 前絞り＋JSON 厳密一致に修正。
  - 正常系: `plan 5678 + user_email 一致` → `+1000`。重複配送 → 変化なし。
  - 異常系: 未知 plan / ユーザー不明 / 未検証 → 200 skip（500 にしない）。署名不正 → 401。
  - エッジ: 大文字メールは一致、小文字化前の prefix 付加は不一致。persona plan 重複は persona 側へ（validation で事前警告）。
- 実装: `app/controllers/freemius_webhooks_controller.rb` 改修（`resolve_wallet_for_topup`・`webhook_user_email`・`find_exact_topup_transaction` 追加、`handle_wallet_topup_completed` 置換、refund 厳密化）。
- 検証: `spec/requests/freemius_webhooks_spec.rb` 既存維持＋新規 fixed 5 例（map 加算・大文字/ prefix・未知 skip・冪等・prefix 混同）。persona 購入ゼロ残高例を `persona_purchases_spec` に追加。

## 単位4: 直接購入維持＋UI 導線（併用ルール可視化）

- 振る舞い:
  - (b) 直接購入は無変更。残高ゼロでも checkout URL 返却（spec で固定）。`already_purchased` 維持。
  - UI: 残高不足時はチャージ＋購入の Gold ボタン2つ＋ `wallet_insufficient_with_purchase`（残高がなくても買える旨）。`purchase_required` は購入ボタンのみ＋ `purchase_without_balance` 付記。固定額モーダルは `denominations` の plan ボタン（JPY＋USD 目安）＋ `topup_fx_note`（USD 建て・変動明示）＋ `purchase_without_balance`。dev は従来 custom 維持（固定額あり＋dev の両立時は両表示）。既存 Gold 統一（#33）維持。新規文言は `lamprey.chat.*` 経由（直書き禁止）。
  - 正常系: 不足 → 2 ボタン表示。固定額あり → plan 選択→redirect。dev のみ → custom→confirm。
  - 異常系: status 失敗 → 楽観表示維持（サーバーが正）。plan 無効 → `topup_invalid_plan`。503 → `wallet_topup_unavailable_reason`。
- 実装: `ChatPanelApp.js`（i18n 追加・Modal 固定額対応・fetchTopupStatus 拡張・handleError/handleSend 併用化・MessageBubble 2 ボタン化）、`ja.yml`・`en.yml`・`chat_panel_helper.rb`。
- 検証: `node --check`＋webpack 開発ビルド（生成物コミットなし）。文言キー存在 grep。

## 単位5: 併用ルール記録＋検証

- 振る舞い: 既定は直接購入、残高は任意前払い、トークン消費は残高、不足時は上記導線、通貨 USD 固定・円は目安、MAP が唯一の正、Stripe 不使用を Issue #46 コメント＋ `documents/guides/freemius_production_setup.md` §3/§4/§6/§8 に記録。
- 検証: 対象指定 `bundle exec rspec`（`wallet_topup_spec`・`persona_purchases_spec`・`freemius_webhooks_spec`・`freemius_pricing_spec`・新規 `freemius_topup_plans_spec`）。全体緑は主張しない（flake）。`bundle exec rubocop` を変更ファイルに実行。フロント変更時は webpack ビルド。実 API 到達確認のみ（カード決済なし）。新 migration なしのため `structure.sql` 更新なし。
