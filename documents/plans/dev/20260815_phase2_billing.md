# Phase 2: 決済・課金システム 実装計画

## 概要

Capafy AI clone の課金システムを実装する。3つの課金モデル（サブスク+従量、プリペイド従量、自動リチャージ付きサブスク）と、ウォレット/クレジットシステムを構築する。

## 振る舞い定義（BDD）

### 課金モデル

| モデル | 振る舞い | 入力 | 出力 |
|--------|---------|------|------|
| ① subscription | 月額固定+超過従量 | チャット使用 | 期間超過分をウォレットから扣除 |
| ② pay_per_use | 純粋従量課金 | チャット使用 | 使用量×単価をウォレットから全額扣除 |
| ③ subscription_with_overage | ① + 残高閾値で自動リチャージ | チャット使用 | ① + 残高不足時に自動チャージ |

### ウォレット

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| topup! | 金額を加算 | balance_cents 増加、credit_transactions に記録 |
| deduct_for_usage! | 金額を扣除 | balance_cents 減少、不足時は InsufficientBalanceError |
| auto_recharge! | 月上限チェック後に自動チャージ | Stripe で決済、成功時に balance_cents 増加 |
| below_threshold? | 閾値との比較 | 残高 < 閾値 で true |

### 請求処理

| モデル | 振る舞い | 計算ロジック |
|--------|---------|------------|
| subscription | 期間超過分のみ課金 | (累計トークン - 含まれるトークン) × 単価 |
| pay_per_use | 全量課金 | 総トークン × 単価 |
| subscription_with_overage | ①と同様 + 自動リチャージ | ① + 閾値下で自動チャージ |

## 作成対象ファイル

### 新規作成

1. `config/billing.yml` — 課金設定ファイル
2. `app/services/billing_config.rb` — 設定読み込みサービス
3. `db/migrate/20260815000001_create_wallets.rb` — ウォレットテーブル
4. `db/migrate/20260815000002_create_credit_transactions.rb` — クレジット取引テーブル
5. `db/migrate/20260815000003_create_user_plan_subscriptions.rb` — サブスクリプションテーブル
6. `db/migrate/20260815000004_create_usage_records.rb` — 使用量記録テーブル
7. `app/models/wallet.rb` — ウォレットモデル
8. `app/models/credit_transaction.rb` — クレジット取引モデル
9. `app/models/user_plan_subscription.rb` — サブスクリプションモデル
10. `app/models/usage_record.rb` — 使用量記録モデル
11. `app/jobs/auto_recharge_check_job.rb` — 自動リチャージジョブ
12. `app/services/billing_service.rb` — 請求処理サービス

### 修正対象

13. `db/seeds.rb` — 課金設定のシードデータ追加

## コードベース規約

- `listings.id` は `int`（32-bit）。FK は `t.references` を使わず `t.integer` + 手動 `add_foreign_key` を使う
- `people.id` も `int`（32-bit）。FK は同様に `t.integer` + 手動 `add_foreign_key`
- `ai_models.id` は `bigint`（通常の `t.references` が使える）
- `communities.id` は `int`（32-bit）。FK は同様に `t.integer` + 手動 `add_foreign_key`
- マイグレーションは `ActiveRecord::Migration[6.1]` を継承（既存パターンに合わせる）
- Jobs は `Struct.new(:param)` + `DelayedAirbrakeNotification` を含む（既存パターン）
- Statesman でステートマネジメント
- 関連不存在時は `optional: true` を付与
- `person` テーブルの FK は `person_id` というカラム名（Sharetribe パターン）

## 既知の制約

- `chat_sessions` テーブルは Phase 3 で作成予定。`chat_session_id` の FK は SQLite では制約を付けず、コメントで示すだけにする
- Stripe の実際の API 連携は Phase 4/5 で実装。ここではモデルとサービスの骨格のみ
- Statesman のトランジション追加は既存 `transaction_transitions` テーブルに影響を与えない（新しいカラム追加なし）
