# Issue #18: 購入フローが動作せず、ペルソナを利用できない — 実装計画

作成日: 2026-10-23
対象: routeflags/agent-bank（AI ペルソナマーケットプレイス「楽市楽問」/ Lamprey）
ブランチ: `feat/agent-bank`
関連 Issue: routeflags/agent-bank#18

---

## 1. 背景と現状（コードで確認した事実）

| # | 事実 | 根拠 |
|---|------|------|
| F1 | チャット開始は `UserPlanSubscription`（active）の存在のみで判定される | `app/controllers/api/v1/chat_sessions_controller.rb:82,155` |
| F2 | サブスクリプション作成は取引ステートマシンの `confirmed` / `free` 遷移フックのみ | `app/state_machines/transaction_process_state_machine.rb:59-70, 89-102` |
| F3 | `free` 遷移のフックは「価格が正の場合のみ作成」＝逆ガード。無料ペルソナ（price 0）では作成されず、逆に有料ペルソナのコンタクト（free 遷移）では作成される | 同上 `:96`（`if transaction.listing&.price&.positive?`） |
| F4 | ペルソナ購入の UI / API は未実装。購入 CTA は「準備中」を表示するスタブ | `client/app/startup/ChatPanelApp.js:1046-1058` |
| F5 | チャットパネルは `default_run_mode == 'run_online'` の出品のみマウントされる | `app/views/listings/show.haml:277-280` |
| F6 | `FreemiusClient.configured?` は `FREEMIUS_API_KEY` の有無のみ。オーナー環境の `.env` に Freemius キーは無い | `app/services/freemius_client.rb:75-83` |
| F7 | ウォレットチャージには開発用の擬似決済（`dev_mode_topup?` = development かつ Stripe 未設定）が既にある | `app/controllers/api/v1/wallet_topup_controller.rb:213-216` |
| F8 | チャット実行には残高 ≥ 10 cents とウォレットが必要 | `app/jobs/persona_executor_job.rb:37,60-72` |
| F9 | 本番の決済は Freemius（Merchant of Record）へ移行中だが、サブスクリプション作成の実 API 経路は未実装 | `documents/plans/dev/20261015_freemius_payment.md` §2-2, §3.3 |

**結論**: 実課金なしで「購入→チャット」を通すには、開発/テスト専用の購入付与経路が必要。
同時に、無料ペルソナの権利判定（F3）と、`free` 遷移の逆ガード（F3）が本 Issue の範囲。

---

## 2. スコープ

### 実施する

1. 開発/テスト専用の購入付与（HTTP API + Rake タスク）。明示的な環境フラグと `Rails.env` の二重ガードで本番では絶対に有効化しない。
2. 無料ペルソナは購入なしでチャット開始できる権利判定に変更。
3. `free` 遷移での誤付与（有料ペルソナのコンタクトで購入権利＋初回トークンが付与される）を修正。
4. フロントの購入 CTA を、開発購入が有効な環境では実際に購入→チャット再開できる導線にする（無効な環境は従来どおり「準備中」）。
5. 再現手順の文書化と、上記の振る舞いに対するテスト追加。

### 実施しない（オーナー承認／別 Issue）

- Freemius の実 API キー投入、実決済、Webhook 実疎通（`FREEMIUS_API_KEY` / `FREEMIUS_WEBHOOK_SECRET`）。
- 本番向けの購入導線（Freemius Checkout からのサブスクリプション作成フロー）の実装。
- 無料ペルソナのトークン課金を完全無料化する変更（現状は購入価格 0 でもトークン原価は課金される。§7 参照）。
- GitHub Issue へのコメント・PR 作成・push。

---

## 3. 振る舞い定義（BDD）

### T1. サブスクリプション作成の共通入口（`UserPlanSubscriptionService`）

取引以外（開発購入）からも同じロジックを使えるよう、`create_for` を追加し `create_on_purchase` を委譲にする。

| # | 前提 | 操作 | 期待する振る舞い |
|---|------|------|------------------|
| T1-1 | person × listing に active な subscription が無い | `create_for(person:, listing:, payment_reference: "dev_...")` | active な `UserPlanSubscription` を 1 件作成。`billing_model` は `token_based`。`duplicate? == false` |
| T1-2 | 同上 | 同上 | Wallet を新規作成し初回トークン（`BillingConfig.included_tokens(:subscription)` × 単価）を topup。`CreditTransaction(topup)` が 1 件 |
| T1-3 | active な subscription が既にある | `create_for` を再度実行 | 新規作成せず既存を返す。`duplicate? == true`。Wallet 残高は不変 |
| T1-4 | confirmed 済み取引 | `create_on_purchase(transaction)` | 従来と同じ結果（`payment_reference` は `initial_purchase_<transaction.id>`）。既存スペックが回帰しない |

### T2. 開発専用ゲート + 購入サービス（`DevPersonaPurchase`）

| # | 前提 | 操作 | 期待する振る舞い |
|---|------|------|------------------|
| T2-1 | `Rails.env.production?` | `enabled?` | `false`（`LAMPREY_ENABLE_DEV_PURCHASE` の値に関わらず常に false） |
| T2-2 | development かつ `LAMPREY_ENABLE_DEV_PURCHASE` 未設定 | `enabled?` | `false`（既定は無効） |
| T2-3 | development / test かつ `LAMPREY_ENABLE_DEV_PURCHASE=true` | `enabled?` | `true` |
| T2-4 | ゲート無効 | `purchase!(person:, listing:)` | `DisabledError` を送出し、DB は変化しない |
| T2-5 | ゲート有効・未購入 | `purchase!(person:, listing:)` | subscription 作成＋初回トークン付与（T1-1/T1-2 と同じ） |
| T2-6 | ゲート有効・購入済み | `purchase!` を再度実行 | `duplicate? == true`、新規作成なし |

### T3. 開発購入 API（`POST /api/v1/dev/persona_purchases`）

| # | 前提 | リクエスト | 期待する振る舞い |
|---|------|-----------|------------------|
| T3-1 | 未ログイン | `POST` | 401 `{ error: "ログインが必要です" }` |
| T3-2 | ログイン済み・ゲート無効 | `POST listing_id: <id>` | 404（本番では存在しないものとして扱い、導線も広告しない） |
| T3-3 | ログイン済み・ゲート有効・listing 不在 | `POST listing_id: 999999` | 404 `{ error: "ペルソナが見つかりません" }` |
| T3-4 | ログイン済み・ゲート有効・未購入 | `POST listing_id` | 201 `{ persona_purchase: { subscription_id, listing_id, status: "active", billing_model, duplicate: false } }`。subscription が 1 件作成される |
| T3-5 | ログイン済み・ゲート有効・購入済み | 再度 `POST` | 200 `duplicate: true`。`UserPlanSubscription` は増えない |
| T3-6 | ゲート有効でも listing が自分の出品 | `POST` | 201（開発検証のため許可。本番の購入フローとは別物である旨をコメントで明記） |

### T4. Rake タスク（`lamprey:dev:grant_persona`）

| # | 前提 | 操作 | 期待する振る舞い |
|---|------|------|------------------|
| T4-1 | production | `bin/rails lamprey:dev:grant_persona[...]` | 何もせず中断（`abort`） |
| T4-2 | development/test・listing/person 解決可 | 実行 | subscription を作成し、`subscription.id` と person/listing を標準出力。2 回目は duplicate を表示 |
| T4-3 | listing または person が解決不可 | 実行 | 理由を表示して中断（例外を投げっぱなしにしない） |

### T5. 無料ペルソナの権利判定（購入不要の導線）

| # | 前提 | 操作 | 期待する振る舞い |
|---|------|------|------------------|
| T5-1 | `Listing#free_to_use?` が true（`price_cents` が 0/nil、または `default_run_mode == 'free'`） | `POST /api/v1/chat_sessions` | 403 にならず 201。subscription 無しでもチャット開始できる |
| T5-2 | 有料 listing（price > 0）・未購入 | 同上 | 従来どおり 403 `purchase_required` |
| T5-3 | 有料 listing・購入済み | 同上 | 201。`billing_model` は subscription の値 |
| T5-4 | 無料 listing | `resolve_billing_model` | subscription が無い場合は `token_based`（= トークン原価はウォレットから課金。既存仕様どおり） |

### T6. `free` 遷移の誤付与修正

| # | 前提 | 操作 | 期待する振る舞い |
|---|------|------|------------------|
| T6-1 | 有料ペルソナ（price > 0）へコンタクト | `create_contact` → 取引が `free` へ遷移 | `UserPlanSubscription` は作成されない。Wallet 残高も増えない（現状は作成されてしまう逆ガードを修正） |
| T6-2 | 無料ペルソナ（price 0）へコンタクト | 同上 | 同上（subscription は作らない。無料ペルソナの利用可否は T5-1 で判定） |
| T6-3 | 有料ペルソナの購入（Stripe preauthorize → capture） | `confirmed` 遷移 | 従来どおり subscription 作成＋初回トークン付与（既存機能を維持） |

### T7. フロント導線（ChatPanel）

| # | 前提 | 操作 | 期待する振る舞い |
|---|------|------|------------------|
| T7-1 | `dev_purchase_enabled` が false（本番・既定の dev） | 403 の購入ボタンを押す | 従来どおり「このペルソナの購入ページは現在準備中です。」を表示 |
| T7-2 | `dev_purchase_enabled` が true | 購入ボタンを押す | `POST /api/v1/dev/persona_purchases` → 成功後に `createSession()` を再実行し、成功メッセージ（`lamprey.chat.dev_purchase_success`）を表示。残高表示も更新される |
| T7-3 | 同上 | API が失敗（404/500 等） | `lamprey.chat.dev_purchase_failed` を表示し、例外を投げない |
| T7-4 | React 16.1.1 | 実装 | クラスコンポーネントのまま（フック禁止）。`chat_panel_helper.rb` の i18n キーと props を同期させる |

### T8. ドキュメント

| # | 期待する振る舞い |
|---|------------------|
| T8-1 | `documents/guides/` に「購入→チャット」の再現手順（前提、環境変数名、手順、期待結果、トラブルシュート）を日本語で記載 |
| T8-2 | Freemius 未設定時の挙動（開発購入で代替 / 本番は購入導線未実装で「準備中」）と、必要な環境変数名（値は書かない）・投入手順・オーナー承認事項を明記 |
| T8-3 | 無料ペルソナ（price 0 / run mode free）の扱いと、トークン原価が発生する既知の制約を明記 |

---

## 4. タスク分担（実装順）

| 順 | タスク | 主な変更ファイル | テスト |
|----|--------|------------------|--------|
| 1 | T1 サービス共通化 | `app/services/user_plan_subscription_service.rb` | `spec/services/user_plan_subscription_service_spec.rb`（追加） |
| 2 | T2 ゲート/サービス | `app/services/dev_persona_purchase.rb`（新規） | `spec/services/dev_persona_purchase_spec.rb`（新規） |
| 3 | T3 API | `app/controllers/api/v1/dev/persona_purchases_controller.rb`（新規）、`config/routes.rb` | `spec/requests/api/v1/dev_persona_purchases_spec.rb`（新規） |
| 4 | T4 Rake | `lib/tasks/lamprey_dev.rake`（新規） | 手動実行で確認（自動テストは付けない） |
| 5 | T5 無料ペルソナ | `app/models/listing.rb`、`app/controllers/api/v1/chat_sessions_controller.rb` | `spec/requests/api/v1/chat_sessions_spec.rb`（追加）、`spec/models/listing_spec.rb`（追加） |
| 6 | T6 free 遷移修正 | `app/state_machines/transaction_process_state_machine.rb` | `spec/requests/transactions_free_flows_spec.rb`（追加） |
| 7 | T7 フロント | `client/app/startup/ChatPanelApp.js`、`app/helpers/chat_panel_helper.rb`、`app/views/listings/show.haml`、`config/locales/{ja,en}.yml` | webpack ビルドで検証（自動テストなし） |
| 8 | T8 ドキュメント | `documents/guides/dev_persona_purchase_flow.md`（新規） | — |

---

## 5. 制約・非機能

- **本番ガード**: 開発購入は `Rails.env.production?` で必ず false。`development`/`test` でも環境フラグ `LAMPREY_ENABLE_DEV_PURCHASE` が true のときのみ有効。
- **既存プロセスを止めない**: ポート 3000/3306 を占有する Docker スタックは起動しない。テストはローカル（MySQL は既存の `sharetribe_test`）で実行する。
- **コーディング規約**: コントローラのモジュール名は `API`（`inflect.acronym 'API'`）。React はクラスコンポーネント。スタイルは既存の API コントローラの `skip_before_action` リストを踏襲。
- **セキュリティ**: 既存の `wallet_topup` の擬似決済と同水準の開発専用ガード。購入を偽装できる経路を本番に残さない。

---

## 6. Plan Architect レビュー結果（セルフレビュー）

> 補足: 本セッションでは `/plan-architect` スキルが利用できないため、`.github/agents/plan-architect.agent.md` のチェック項目に沿ってコードベースを直接確認した。また 2026-10-20 の運用変更により `documents/plans/dev/issues/` へのファイル保存は廃止されているため、指摘は本節に記録する（GitHub Issue への書き込みは本タスクで禁止）。

| 優先度 | 指摘 | 対応 |
|--------|------|------|
| 🔴 高 | `free` 遷移フックが逆ガード。有料ペルソナのコンタクトで購入権利＋初回トークン（約 200,000 cents）が付与される | T6 として修正対象に追加 |
| 🔴 高 | 開発購入は本番に残ると購入偽装になる | `Rails.env.production?` を最初に評価するゲートを必須化（T2） |
| 🟡 中 | サブスクリプション作成ロジックの二重実装リスク | `UserPlanSubscriptionService` を `create_for` として共通化し、開発購入も同じ入口を使う（T1） |
| 🟡 中 | 既存の開発用擬似決済（`dev_mode_topup?`）とガード水準が不揃い | 同じ「環境 + フラグ」方式に合わせ、コメントで相互参照（T2, T7） |
| 🟡 中 | チャットパネルは `run_online` のみマウント（F5）。「無料ペルソナ」の意味が 2 つある | T5 は権利判定（price 0 / run mode free）、T7 は `run_online` の購入導線と切り分け、ドキュメントに明記（T8-3） |
| 🟡 中 | i18n キーは `chat_panel_helper.rb` の網羅リストとセットでないと undefined になる | T7 で helper と locales を同時更新 |
| 🟢 低 | `person.wallet` は community スコープ | `Person#find_or_create_wallet!` を経由（既存サービスをそのまま利用） |
| 🟢 低 | Rake タスクはテストされない | 実行結果を検証記録に残す（T4） |

**判定**: 上記を計画に反映済み。実装へ進む。

---

## 7. 既知の制約・残課題

1. 本番の購入導線は未実装のまま。Freemius の API キー・Webhook シークレット投入と `subscription.created` を起点にした購入フロー設計が必要（オーナー承認事項）。
2. 無料ペルソナでも、チャット実行時にトークン原価（`token_based` 課金）と残高 ≥ 10 cents が必要。完全無料化は課金設計の変更であり別 Issue。
3. 開発購入は初回トークンを付与するため、開発環境でも残高が増える（本番では発生しない）。
4. ブラウザ E2E（Playwright）は `client/node_modules` とビルド済みアセット、稼働中サーバーが必要なため、本タスクではリクエストスペックと手動手順の文書化で代替する。

---

## 8. 受入条件との対応

| Issue #18 の受入条件 | 対応 |
|----------------------|------|
| 購入→チャット利用の一連フローが動作する（E2E で確認） | T1–T5 + `spec/requests/api/v1/dev_persona_purchases_spec.rb` → `chat_sessions_spec.rb` の通しシナリオ（購入 → セッション作成 201）。手順は T8-1 に記載 |
| 開発環境での再現手順が文書化されている | T8-1（`documents/guides/dev_persona_purchase_flow.md`） |
| 既存テストが通る | 変更対象の既存スペック + 全体スペックを実行し記録（§9） |

---

## 9. 検証記録（Reviewer / QA）

### 9.1 変更ファイル一覧

| 種別 | ファイル | 要点 |
|------|----------|------|
| 変更 | `app/services/user_plan_subscription_service.rb` | `create_for` を追加し `create_on_purchase` を委譲。取引以外からも同じ入口を使えるようにした |
| 新規 | `app/services/dev_persona_purchase.rb` | 開発購入のゲート（production 常時無効 + 環境フラグ）と付与処理 |
| 新規 | `app/controllers/api/v1/dev/persona_purchases_controller.rb` | `POST /api/v1/dev/persona_purchases`（無効時は 404） |
| 変更 | `config/routes.rb` | `api/v1/dev` 名前空間を追加 |
| 新規 | `lib/tasks/lamprey_dev.rake` | `lamprey:dev:grant_persona[listing_id,person]` |
| 変更 | `app/models/listing.rb` | `Listing#free_to_use?` を追加 |
| 変更 | `app/controllers/api/v1/chat_sessions_controller.rb` | 無料ペルソナは購入不要で `purchased?` を通過 |
| 変更 | `app/state_machines/transaction_process_state_machine.rb` | `free` 遷移での購入権利付与を削除（逆ガードの修正） |
| 変更 | `app/helpers/chat_panel_helper.rb` / `app/views/listings/show.haml` / `client/app/startup/ChatPanelApp.js` / `config/locales/{ja,en}.yml` | 購入 CTA の開発導線と i18n |
| 新規 | `spec/requests/api/v1/dev_persona_purchases_spec.rb` ほか 5 スペック | §9.3 参照 |
| 新規 | `documents/guides/dev_persona_purchase_flow.md` | 再現手順 |
| 新規 | 本文書 | 計画・検証記録 |

### 9.2 Reviewer 観点の確認

| 観点 | 結果 |
|------|------|
| 重複実装の防止 | 購入権利の作成は `UserPlanSubscriptionService` に一本化（開発購入も同サービス経由） |
| 本番に購入偽装経路を残さない | `Rails.env.production?` を最初に評価。HTTP はフラグ未設定なら 404。スペックで固定 |
| 既存の決済経路への影響 | `confirmed` 遷移（実決済）の付与は維持（`spec/services/persona_purchase_entitlement_spec.rb` で担保） |
| アーキテクチャ | コントローラは `API::V1::Dev`（`inflect.acronym 'API'`）。既存 API コントローラの `skip_before_action` を踏襲 |
| React 制約 | フック不使用（クラスコンポーネントのメソッド追加のみ） |
| i18n | `chat_panel_helper.rb` の網羅リストと `ja.yml` / `en.yml` を同時更新 |
| セキュリティ | 開発購入は「認証済み + フラグ + 非 production」でのみ動作。付与内容は購入と同じ（初期トークン含む） |
| 残余リスク | 共有開発環境でフラグを有効にすると、任意のログインユーザーが自己付与できる。既定は無効であり、必要なときだけ有効化する運用（ガイドに明記） |

### 9.3 QA: 実行したコマンドと結果

| コマンド | 結果 |
|----------|------|
| `bundle install` | 成功（検証環境の前提準備） |
| `bundle exec rspec`（全体） | **1409 examples, 0 failures** |
| `bundle exec rspec spec/requests` | 301 examples, 0 failures |
| `bundle exec rspec spec/models` | 192 examples, 0 failures |
| `bundle exec rspec spec/services` | 371 examples, 0 failures |
| `bundle exec rubocop <変更ファイル>` | 1 offense（`transaction_process_state_machine.rb:67` の `rescue => e`）が既存コードに存在。今回の変更では新規指摘なし |
| `RAILS_ENV=test rails zeitwerk:check` | `Otherwise, all is good!` |
| `RAILS_ENV=test rails routes` | `api_v1_dev_persona_purchases POST /api/v1/dev/persona_purchases` |
| `webpack --mode=development --config webpack.client.config.js` | コンパイル成功（警告 25 件は既存の未生成ファイル由来）。出力 `chat_panel-bundle.js` に `dev_purchase_success` を含むことを確認 |
| `RAILS_ENV=test rails runner "...DevPersonaPurchase.enabled?"` | `false`（フラグ未設定時の既定値を確認） |

### 9.4 QA: 未実行の検証と理由

| 検証 | 理由 |
|------|------|
| ブラウザ E2E（Playwright `spec/e2e/navigation_spec.js`） | 稼働中のサーバー・ビルド済みアセット・ブラウザ起動が必要。さらに実際のチャット応答には外部 AI API 呼び出し（外部送信・課金）が必要で本タスクの制約で禁止。代わりにリクエストスペックで「購入 → チャットセッション作成」を通しで検証し、手順をガイドに記載 |
| Freemius サンドボックスでの実決済 | API キー未投入・実課金禁止のため未実行 |
| Docker 環境（`docker-compose.dev.yml`）での検証 | イメージ未ビルド、ポート 3000/3306 を占有するため起動せず。ローカル（既存の `sharetribe_test`）で検証 |

### 9.5 `free` 遷移の逆ガード修正の実測（変更前後の比較）

有料ペルソナ（価格 2,000 USD）にコンタクトした直後の DB 状態を、変更前後で比較した。

| 実行 | `UserPlanSubscription` | 取引状態 | ウォレット残高 |
|------|:----------------------:|:--------:|:--------------:|
| 変更前（base コミット） | **1 件作成** | `free` | **200,000 cents 付与** |
| 変更後（本タスク） | 0 件 | `free` | なし（ウォレット未作成） |

コンタクトだけで購入権利と初回トークンが得られていたことが確認でき、修正によって
「決済なしの取引では購入権利を付与しない」振る舞いになった。

### 9.6 環境差分の注記
作業コピーには git 管理外の生成物（`config/database.yml`、`.env`、ビルド済みアセット、`node_modules`）が
無いため、初回計測ではビュー描画系スペックが 84 件失敗した。メインのチェックアウトからこれらを補った
後はすべて成功している（**コードの変更による失敗ではない**。補う前も base コミットと同一の 84 件で
あり、差分がないことを確認済み）。
