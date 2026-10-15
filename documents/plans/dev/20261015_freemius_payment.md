# 開発指示書: Freemius 決済の導入

作成日: 2026-10-15
対象: routeflags/agent-bank（AI ペルソナマーケットプレイス「楽市楽間」/ Lamprey）
ブランチ: `feat/agent-bank`

---

## 1. 背景と目的

現在の決済は Stripe 直接連携（`WalletTopupController` が `Stripe::PaymentIntent` を作成・検証）で実装されている。
しかし Stripe は日本を含むグローバル展開で VAT・消費税・チャージバック対応を自前で行う必要がある。

[Freemius](https://freemius.com/) はソフトウェア販売向けの Merchant of Record（MoR）であり、
決済・サブスクリプション・税務コンプライアンス・ライセンス管理を一括で肩代わりする。
本指示書では、既存のウォレット/サブスクリプション/使用量記録の仕組みを維持したまま、
**決済プロバイダーを Stripe 直接連携から Freemius に置き換える**手順を定義する。

### 参照

- Freemius 公式: https://freemius.com/
- 開発者ダッシュボード: https://freemius.com/help/documentation/getting-started/explore-the-developer-dashboard/
- REST API: https://freemius.com/help/api/ （認証: Bearer トークン）
- Webhook（JS SDK）: https://freemius.com/help/documentation/saas-sdk/js-sdk/webhooks/
- Checkout: https://freemius.com/help/documentation/saas-sdk/js-sdk/checkout/

---

## 2. 現状の決済アーキテクチャ（置き換え対象）

### 2.1 決済フロー（現状: Stripe 直接連携）

```
[ChatPanel: WalletTopupModal]
  │ 1. POST /api/v1/wallet_topup { amount_cents }
  ▼
[WalletTopupController#create]
  │ Stripe::PaymentIntent.create → client_secret 返却
  ▼
[フロント: Stripe.js でカード決済確定]
  │ 2. POST /api/v1/wallet_topup/confirm { payment_intent_id }
  ▼
[WalletTopupController#confirm]
  │ Stripe::PaymentIntent.retrieve → status == "succeeded" を確認
  │ 冪等性チェック（同一 PI で二重チャージ防止）
  ▼
[Wallet#topup!] → balance_cents 加算 + CreditTransaction 記録
```

### 2.2 関連ファイル一覧

| 役割 | ファイル | 行数 | 備考 |
|------|---------|------|------|
| ウォレットチャージ API | `app/controllers/api/v1/wallet_topup_controller.rb` | 220行相当 | `create` / `confirm` / `balance` + dev モード |
| ウォレット | `app/models/wallet.rb` | — | `topup!` / `deduct_for_usage!` / `auto_recharge!` |
| 請求計算 | `app/services/billing_service.rb` | — | 双方向コミッション（Model A/B） |
| 請求設定 | `app/services/billing_config.rb` + `config/billing.yml` | — | 3課金モデル、通貨 USD |
| サブスクリプション | `app/models/user_plan_subscription.rb` | — | 状態遷移マシン付き |
| 使用量記録 | `app/models/usage_record.rb` | — | トークン使用量 |
| 自動チャージ Job | `app/jobs/auto_recharge_check_job.rb` | — | 残高不足時の自動リチャージ |
| ルーティング | `config/routes.rb:729` | — | `wallet_topup#create/confirm/balance` |
| フロント決済 UI | `client/app/startup/ChatPanelApp.js:191-280` | `WalletTopupModal` | 金額選択→決済→残高更新 |
| Gem | `Gemfile:84` | `gem 'stripe', '~> 5.55.0'` | 削除候補 |

### 2.3 維持するもの（変更しない）

- `Wallet` / `CreditTransaction` / `UserPlanSubscription` / `UsageRecord` のスキーマとビジネスロジック
- `BillingService` のコミッション計算（Model A/B）
- `config/billing.yml` の価格設定
- フロントの `WalletTopupModal` の UX（金額選択・残高表示）は維持し、決済実行部分のみ差し替え

---

## 3. Freemius 導入設計

### 3.1 全体方針

**Freemius を Merchant of Record として利用し、Stripe 直接連携を置き換える。**

```
[ChatPanel: WalletTopupModal]
  │ 1. POST /api/v1/wallet_topup { amount_cents }
  ▼
[WalletTopupController#create]（改修）
  │ Freemius Checkout セッション作成（ホスト型 or 埋め込み型）
  │ → checkout_url 返却
  ▼
[フロント: Freemius Checkout へリダイレクト/埋め込み]
  │ ユーザーが Freemius 側で決済完了
  ▼
[Freemius → Webhook: payment.completed]
  ▼
[FreemiusWebhooksController#payment_completed]（新規）
  │ 署名検証（x-signature）→ 金額・ユーザー特定
  │ 冪等性チェック（Freemius payment_id で二重チャージ防止）
  ▼
[Wallet#topup!] → balance_cents 加算 + CreditTransaction 記録
```

### 3.2 なぜ Webhook 駆動にするか

- Freemius は MoR として決済完了をサーバー間通知するのが正規フロー
- フロントの `confirm` ポーリングは不要になり、決済状態の不整合（未確定のまま残高加算など）を防げる
- 既存の `confirm` エンドポイントは後方互換のため残すが、Freemius 移行後は Webhook が正とする

### 3.3 サブスクリプション対応

Freemius の Subscriptions API でプラン・更新・解約を管理する。
`UserPlanSubscription` の `status` は Freemius の `subscription.*` イベント
（`created` / `renewed` / `cancelled` / `expired` / `renewal.failed`）で同期する。

| Freemius イベント | 対応する処理 |
|-------------------|-------------|
| `subscription.created` | `UserPlanSubscription` 作成（status: active） |
| `subscription.renewed` | 期間更新 |
| `subscription.cancelled` / `expired` | status を cancelled/expired に遷移 |
| `subscription.renewal.failed` | 管理者通知・ユーザーへの再決済案内 |
| `payment.completed` | `Wallet#topup!` でチャージ |
| `payment.refunded` | 対応する `CreditTransaction` を逆仕訳（返金記録） |

---

## 4. 実装タスク

### Phase 1: 準備（Freemius アカウント・設定）

- [ ] **1-1.** Freemius アカウント作成・製品登録（Developer Dashboard）
  - 製品名: 楽市楽間 / Lamprey
  - 通貨: USD（現行 `config/billing.yml` と一致）
- [ ] **1-2.** プラン定義（Freemius Dashboard の Plans）
  - `config/billing.yml` の3モデルに対応するプランを作成
  - subscription / pay_per_use / subscription_with_overage
- [ ] **1-3.** API 認証情報の発行（Developer / App  scope の Bearer トークン）
  - 本番: `FREEMIUS_API_KEY`（環境変数・Secrets 管理）
  - 開発: サンドボックスキー
- [ ] **1-4.** Webhook URL の登録（Freemius Dashboard → Integrations → Webhooks）
  - 本番: `https://<本番ドメイン>/webhooks/freemius`
  - 署名検証用のシークレット取得

### Phase 2: バックエンド実装

- [x] **2-1.** `FreemiusClient` サービスクラスを新規作成（`app/services/freemius_client.rb`）
  - Bearer トークン認証の Faraday/Net::HTTP ラッパー
  - Checkout セッション作成・Payments 照会・Subscriptions 照会
  - 既存の `Ai::StreamingClient` のような薄いラッパーでよい
- [x] **2-2.** `FreemiusWebhooksController` を新規作成（`app/controllers/freemius_webhooks_controller.rb`）
  - ルート: `POST /webhooks/freemius`（`config/routes.rb` に追加、PayPal IPN と同列）
  - `x-signature` ヘッダーで署名検証（不正リクエストは 401）
  - イベント種別でディスパッチ（`payment.completed` / `subscription.*` / `payment.refunded`）
  - 冪等性: Freemius の `payment_id` / `subscription_id` で重複処理を防止
- [x] **2-3.** `WalletTopupController#create` を改修
  - Stripe PaymentIntent 作成 → Freemius Checkout セッション作成に置き換え
  - レスポンスに `checkout_url` を含める（フロントはここへ遷移）
  - dev モード（擬似 PaymentIntent）は開発用に残す
- [x] **2-4.** `Wallet#topup!` の監査証跡を拡張
  - `stripe_payment_id:` 引数に加え `freemius_payment_id:` を受け付ける
  - `CreditTransaction.metadata` に `{ freemius_payment_id: ... }` を記録
- [x] **2-5.** `UserPlanSubscription` と Freemius Subscription の同期
  - `freemius_subscription_id` カラム追加のマイグレーション
  - `subscription.created/renewed/cancelled/expired` で状態遷移
- [ ] **2-6.** `AutoRechargeCheckJob` の決済実行を Freemius 経由に変更
  - 保存済み決済手段での off-session 課金が Freemius で可能か確認
  - 不可の場合はユーザーへの手動チャージ誘導にフォールバック

### Phase 3: フロントエンド実装

- [x] **3-1.** `WalletTopupModal`（`ChatPanelApp.js:191-280`）の決済実行を差し替え
  - `POST /api/v1/wallet_topup` → 返却された `checkout_url` へリダイレクト（または埋め込み Checkout）
  - `confirm` ポーリングは削除し、Webhook 完了後の残高ポーリング（`balance` API）に変更
- [ ] **3-2.** 決済完了後の UX
  - Freemius Checkout からの戻り先（success/cancel URL）を定義
  - 成功時: 残高を再取得して表示更新＋完了メッセージ
  - キャンセル時: 中断メッセージ
- [x] **3-3.** ロケール追加（`config/locales/ja.yml` / `en.yml` の `lamprey.chat` 配下）
  - リダイレクト案内・完了・キャンセル・エラー時の文言

### Phase 4: 検証

- [x] **4-1.** 単体テスト（RSpec）
  - `FreemiusClient` のリクエスト組み立て（WebMock でスタブ）
  - Webhook 署名検証（正・不正）
  - 冪等性（二重 Webhook で二重チャージされないこと）
  - `subscription.*` イベントでの状態遷移
- [x] **4-2.** 結合テスト（Request spec）
  - `POST /webhooks/freemius` の正常系・異常系
  - `POST /api/v1/wallet_topup` が `checkout_url` を返すこと
- [ ] **4-3.** E2E（開発環境・Freemius サンドボックス）
  - テストカードでチャージ → Webhook → 残高加算を確認
  - サブスクリプション作成→更新→解約のライフサイクル
- [ ] **4-4.** a11y（axe-core）
  - 変更した Checkout 導線の画面で `scripts/a11y_audit.js` を実行し 0違反を確認
- [ ] **4-5.** PageSpeed（Lighthouse）
  - Freemius Checkout 埋め込み型を選んだ場合は追加 JS の影響を `docs/page-speed-report.md` に追記
  - ホスト型（リダイレクト）なら影響なし

### Phase 5: 移行・クリーンアップ

- [ ] **5-1.** Stripe 直接連携コードの削除
  - `WalletTopupController` 内の `Stripe::PaymentIntent` 呼び出し
  - `Wallet#auto_recharge!` 内の Stripe 呼び出し（Freemius 移行後）
  - `Gemfile` の `gem 'stripe'`（他で使用がなければ）
  - `.env` / Secrets の `STRIPE_SECRET_KEY`
- [ ] **5-2.** ドキュメント更新
  - `docs/page-speed-report.md`（Checkout 方式による影響）
  - 本指示書の「実装済み」チェック

---

## 5. 非機能要件

| 項目 | 要件 |
|------|------|
| セキュリティ | Webhook 署名検証は必須。不正リクエストは 401 で拒否しログ記録 |
| 冪等性 | 同一 Freemius `payment_id` の重複 Webhook で二重チャージしないこと（既存の Stripe PI 冪等性と同等） |
| 監査証跡 | すべてのチャージに `freemius_payment_id` を `CreditTransaction.metadata` に記録 |
| a11y | 変更画面で axe-core 0違反（`scripts/a11y_audit.js`） |
| PageSpeed | ホスト型 Checkout を推奨（自ページへの JS 追加なし）。埋め込み型の場合は Lighthouse で影響測定 |
| i18n | 新規 UI 文言は `ja.yml` / `en.yml` の両方に追加（日本市場向けのため日本語優先） |
| 後方互換 | 既存の `confirm` エンドポイントは移行期間中残す（Freemius 移行完了後に削除判断） |

---

## 6. リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| Freemius の手数料・レベニューシェア | 収益性 | 料金改定前に Freemius の料金体系を確認し `config/billing.yml` に反映 |
| Webhook 到達遅延・欠損 | 残高反映の遅れ | フロントは `balance` ポーリングで最終確認。未反映時は再送要求導線 |
| Freemius 障害時の決済停止 | 売上停止 | Stripe 直接連携コードは移行直後に削除せず、フラグで切り戻せるようにする |
| 通貨・税率の差異 | 請求額の不一致 | `BillingService` の計算と Freemius の請求額を Webhook 時に突合し、差異があれば警告ログ |
| 日本の消費税・インボイス対応 | 法務 | MoR である Freemius が税務を肩代わりすることを契約前に確認 |
| 店子（出品者）への按分・分配払い | 出品者報酬の支払い方法 | **Freemius 単体では不可**。Freemius は単一ベンダー（自社）への売上集約・月次 payout が前提で、マーケットプレイス型の複数ベンダーへの自動分配（split payout）機能はない。下記「9. 店子への按分払い」を参照 |

---

## 7. 受け入れ基準（Definition of Done）

1. Freemius サンドボックスでウォレットチャージが完了し、残高に反映されること
2. サブスクリプションの作成・更新・解約が `UserPlanSubscription` に同期されること
3. 同一 Webhook の重複送信で二重チャージが発生しないこと
4. RSpec（単体・結合）がすべて緑であること
5. a11y 監査で 0違反であること
6. PageSpeed への影響を測定・記録していること
7. Stripe 直接連携コードの削除方針が決定していること（削除 or フラグ保持）

---

## 9. 店子（出品者）への按分払い

### 結論: Freemius 単体では不可。自社での按分計算＋別手段での送金が必要

Freemius は**単一ベンダー（自社製品の販売者）向け**の Merchant of Record であり、
マーケットプレイス型の**複数ベンダーへの自動分配（split payout / destination charges）機能はない**。
Freemius の payout は「自社の売上 → 自社口座への月次振込」のみが対象である
（参考: [Getting Paid](https://freemius.com/help/documentation/selling-with-freemius/your-earnings/)）。

そのため、出品者（店子）への報酬支払いは以下の構成になる：

```
[購入者] ──決済──→ [Freemius (MoR)] ──月次payout──→ [自社口座]
                                                      │
                                          ┌───────────┴───────────┐
                                          │ 自社で按分計算・送金   │
                                          ▼                       ▼
                                   [出品者Aの口座]          [出品者Bの口座]
                                   （銀行振込等・別手段）   （銀行振込等・別手段）
```

### 現状の按分計算（再利用可能）

按分比率の計算ロジック自体は既に `BillingService` に実装済みであり、
Freemius 移行後も**計算部分はそのまま使える**：

- `BillingService#calculate_charges`（`app/services/billing_service.rb:44`）
  - `base_cost_cents`（トークン原価 or ペルソナ価格）
  - `platform_commission_cents`（プラットフォーム取り分）
  - `seller_commission_cents`（出品者取り分 ＝ `listing.seller_commission_rate` から算出）
- 出品者取り分率: `listing.seller_commission_rate`（`app/models/listing.rb:429` でバリデーション済み）

### 不足しているもの（実装が必要）

| # | 項目 | 内容 |
|---|------|------|
| 1 | 出品者への支払い実績テーブル | `CreditTransaction` はウォレット（購入者側）の取引のみ。出品者への支払い（payout）を記録するテーブル/transaction_type がない。新規 `seller_payouts` テーブルまたは `CreditTransaction` の拡張が必要 |
| 2 | 送金手段 | Freemius は出品者への送金を行わない。銀行振込（手動 or API）・Stripe Connect・PayPal Payouts 等の別手段が必要。現状 `Stripe::Transfer` / `Stripe::Payout` のラッパー（`stripe_api_wrapper.rb:185-208`）はあるが、呼び出しは Sharetribe 旧取引フロー（`payments.rb:80`）からのみで、AI 課金フローからは未接続 |
| 3 | 支払いサイクル | 月次締め・最低支払額・繰越などの運用ルールの決定。Freemius の月次 payout（毎月1日計算・3〜6営業日で着金）に合わせるのが自然 |
| 4 | 出品者への明細 | 出品者が自分の売上・報酬を確認する画面がない。管理画面 or マイページへの売上ダッシュボード追加が必要 |

### 推奨方針

1. **Phase 1（Freemius 移行時）**: 購入者課金のみ Freemius に移行。出品者報酬は `BillingService` で計算・記録だけ行い、支払いは手動（銀行振込）で運用開始
2. **Phase 2**: `seller_payouts` テーブル＋管理画面の支払い一覧・承認フローを実装
3. **Phase 3**: 送金 API（Stripe Connect / 銀行振込 API）の自動化を検討

---

## 10. 参考: 既存コードへのポインタ

- ウォレットチャージ API: `app/controllers/api/v1/wallet_topup_controller.rb`
- ルーティング: `config/routes.rb:729`（`wallet_topup#create/confirm/balance`）
- Webhook の先例: `config/routes.rb:40`（`post '/webhooks/paypal_ipn'`）
- ウォレット: `app/models/wallet.rb`（`topup!` / `deduct_for_usage!` / `auto_recharge!`）
- 請求計算: `app/services/billing_service.rb`（Model A/B コミッション）
- 請求設定: `config/billing.yml`（3モデル・通貨 USD）
- サブスクリプション: `app/models/user_plan_subscription.rb`
- 自動チャージ: `app/jobs/auto_recharge_check_job.rb`
- フロント決済 UI: `client/app/startup/ChatPanelApp.js:191-280`（`WalletTopupModal`）
- 前回の決済計画書: `documents/plans/dev/20261012_wallet_topup_stripe.md`
