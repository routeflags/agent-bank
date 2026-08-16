# 決済フロー 実装指示書

> **対象**: 開発者（Implementer）
> **作成日**: 2026-08-17
> **前提**: AGENTS.md を読了済み。React 16.1.1（クラスコンポーネント）、Ruby 3.4.10、Rails 8.1.2

---

## 1. ユースケース概要

### 1-1. システム全体ユースケース図（テキストUML）

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Lamprey プラットフォーム                       │
│                                                                     │
│  ┌──────────┐    ┌────────────────┐    ┌──────────────────────┐    │
│  │          │    │                │    │                      │    │
│  │  ユーザー  │───▶│  ペルソナ購入    │───▶│  チャット会話          │    │
│  │          │    │  (定額購入)     │    │  (AI エージェント)     │    │
│  │          │    │                │    │                      │    │
│  │          │◀───│  トークン付与    │◀───│  トークン消費          │    │
│  │          │    │  (初回+追加)    │    │  (UsageRecord)       │    │
│  │          │    │                │    │                      │    │
│  │          │───▶│  クレジット追加  │    └──────────────────────┘    │
│  │          │    │  (ウォレット)   │                                 │
│  └──────────┘    └────────────────┘                                 │
│                                                                     │
│  ┌──────────┐    ┌────────────────┐                                 │
│  │          │    │                │                                 │
│  │  出品者   │───▶│  ペルソナ出品    │                                 │
│  │          │    │  (価格設定)     │                                 │
│  │          │    │                │                                 │
│  │          │◀───│  売上分配       │                                 │
│  │          │    │  (コミッション)  │                                 │
│  └──────────┘    └────────────────┘                                 │
└─────────────────────────────────────────────────────────────────────┘
```

### 1-2. 各ユースケースの詳細

#### UC-1: ペルソナ定額購入

```
アクター: ユーザー（購入者）
前提条件: ユーザーは登録済みでログインしている
主系列:
  1. ユーザーがペルソナ一覧から対象ペルソナを選択する
  2. システムがペルソナ詳細（価格、説明、トークン付与量）を表示する
  3. ユーザーが「購入する」ボタンをクリックする
  4. システムが決済ページ（Stripe/PayPal）を表示する
  5. ユーザーが決済情報を入力し、購入を完了する
  6. システムが Transaction を作成し、状態を completed に更新する
  7. システムが UserPlanSubscription を自動作成する
  8. システムが Wallet に初回トークン（included_tokens）を付与する
  9. ユーザーに「購入完了」メッセージを表示する
代替系列:
  5a. 決済が失敗した場合:
    → システムがエラーメッセージを表示し、主系列 5 に戻る
例外系列:
  - ユーザーが既にこのペルソナを購入済みの場合:
    → システムが「既に購入済み」と表示し、チャット画面に遷移する
```

#### UC-2: チャット会話（トークン消費）

```
アクター: ユーザー（購入済み）
前提条件: ユーザーはペルソナを購入済みで、Wallet にトークンがある
主系列:
  1. ユーザーがチャット画面でメッセージを入力する
  2. システムが Wallet の残高を確認する
  3. システムが AI プロバイダー（OpenAI/Anthropic）にリクエストを送信する
  4. システムが AI レスポンスをストリーミングで受信する
  5. システムが UsageRecord を作成し、トークン使用量を記録する
  6. システムが Wallet からトークンを差し引く
  7. システムがレスポンスをフロントエンドに表示する
代替系列:
  2a. Wallet の残高が不足している場合:
    → システムが「トークンが不足しています。追加購入してください」と表示する
    → チャットは続行できない
例外系列:
  - AI プロバイダーがエラーを返した場合:
    → システムがエラーメッセージを表示し、トークンは差し引かない
```

#### UC-3: クレジット追加購入（ウォレットトップアップ）

```
アクター: ユーザー
前提条件: ユーザーは登録済みでログインしている
主系列:
  1. ユーザーが「クレジットを追加」ボタンをクリックする
  2. システムが現在の残高と追加オプションを表示する
  3. ユーザーが追加する金額を選択する
  4. システムが決済ページ（Stripe）を表示する
  5. ユーザーが決済情報を入力し、購入を完了する
  6. システムが Wallet にトークンを追加する
  7. システムが CreditTransaction（topup）を作成する
  8. ユーザーに「追加完了」メッセージを表示する
代替系列:
  5a. 決済が失敗した場合:
    → システムがエラーメッセージを表示し、主系列 4 に戻る
```

#### UC-4: 自動リチャージ

```
アクター: システム（AutoRechargeCheckJob）
前提条件: ユーザーが自動リチャージを有効にしている
主系列:
  1. AutoRechargeCheckJob が定期的に実行される
  2. システムが全ユーザーの Wallet を確認する
  3. 残高が閾値（threshold_cents）を下回るユーザーを特定する
  4. システムが Stripe で自動リチャージを実行する
  5. システムが Wallet にトークンを追加する
  6. システムが CreditTransaction（auto_recharge）を作成する
例外系列:
  - 月次上限（monthly_cap_cents）に達した場合:
    → 自動リチャージをスキップし、ユーザーに通知する
  - Stripe の決済が失敗した場合:
    → エラーログを記録し、次回のジョブで再試行する
```

---

## 2. 現状の実装状況

### 2-1. 実装済み（✅）

| コンポーネント | ファイル | 状態 |
|---------------|---------|------|
| Wallet モデル | `app/models/wallet.rb` | balance_cents, topup!, deduct_for_usage!, auto_recharge! |
| CreditTransaction モデル | `app/models/credit_transaction.rb` | topup, usage_deduction, auto_recharge, refund |
| UsageRecord モデル | `app/models/usage_record.rb` | input_tokens, output_tokens, cost_cents |
| BillingService | `app/services/billing_service.rb` | 2モデル対応のコミッション計算 |
| BillingConfig | `app/services/billing_config.rb` | YAML ベースの設定管理 |
| AutoRechargeCheckJob | `app/jobs/auto_recharge_check_job.rb` | 定期自動リチャージ |
| PersonaExecutorJob | `app/jobs/persona_executor_job.rb` | AI レスポンス + トークン消費 |
| ChatSession モデル | `app/models/chat_session.rb` | person_id, listing_id, status |
| ChatMessage モデル | `app/models/chat_message.rb` | role, input_tokens, output_tokens |
| ChatSessionsController | `app/controllers/api/v1/chat_sessions_controller.rb` | CRUD + SSE |
| PersonaChatChannel | `app/channels/persona_chat_channel.rb` | WebSocket |
| ChatPanelApp.js | `client/app/startup/ChatPanelApp.js` | 3カラム、Markdown、XSS サン |

### 2-2. 未実装（❌）

| タスク | 優先度 | 説明 |
|--------|:------:|------|
| **購入→サブスクリプション連携** | 🔴 高 | Transaction 完了時に UserPlanSubscription を自動作成 |
| **初回トークン付与** | 🔴 高 | 購入完了時に Wallet に included_tokens を付与 |
| **チャット購入検証** | 🔴 高 | ChatSessionsController で購入済みチェック |
| **手動ウォレットトップアップ API** | 🔴 高 | Stripe PaymentIntent 経由のチャージ API |
| **ウォレットトップアップ UI** | 🟡 中 | チャット UI に残高表示 + トップアップボタン |
| **残高不足時のトップアップ誘導** | 🟡 中 | stream_error に error_type を追加 |
| **billing_model のサーバー側決定** | 🟡 中 | クライアントからの入力を信頼しない |
| **デッドコード削除** | 🟢 低 | PersonaExecutorJob の record_usage_and_deduct! |

---

## 3. 実装タスク詳細

### タスク 1: 購入→サブスクリプション連携

**目的**: ペルソナ購入完了時に、自動的に UserPlanSubscription を作成する

**対象ファイル**:
- `app/models/transaction.rb`（またはコールバック先）
- `app/services/user_plan_subscription_service.rb`（新規作成）

**実装仕様**:

```ruby
# app/services/user_plan_subscription_service.rb
class UserPlanSubscriptionService
  def self.create_on_purchase(transaction)
    # 1. Transaction から listing と person を取得
    listing = transaction.listing
    person = transaction.buyer

    # 2. UserPlanSubscription を作成
    subscription = UserPlanSubscription.create!(
      person: person,
      listing: listing,
      status: 'active'
    )

    # 3. 初回トークンを付与
    assign_initial_tokens(person, listing)

    subscription
  end

  def self.assign_initial_tokens(person, listing)
    billing_config = BillingConfig.new(listing: listing)
    included_tokens = billing_config.included_tokens

    wallet = person.wallet || Wallet.create!(person: person, balance_cents: 0)
    wallet.topup!(
      amount_cents: included_tokens * billing_config.per_token_price_cents,
      source: 'initial_purchase'
    )
  end
end
```

**受け入れ条件**:
- [ ] Transaction 完了時に UserPlanSubscription が自動作成される
- [ ] 購入時に Wallet に初回トークンが付与される
- [ ] 同じペルソナを二重購入できない（既存サブスクリプションがある場合）
- [ ] 決済失敗時はサブスクリプションが作成されない

---

### タスク 2: チャット購入検証

**目的**: 未購入ユーザーがチャットできないようにする

**対象ファイル**:
- `app/controllers/api/v1/chat_sessions_controller.rb`

**実装仕様**:

```ruby
# app/controllers/api/v1/chat_sessions_controller.rb

before_action :verify_purchase, only: [:create]

def create
  listing = Listing.find(params[:listing_id])

  # 購入検証
  unless purchased?(current_user, listing)
    render json: { error: 'このペルソナを購入してください' }, status: :forbidden
    return
  end

  # 既存セッションがある場合はそれを返す
  existing = ChatSession.find_by(person: current_user, listing: listing)
  if existing
    render json: existing, status: :ok
    return
  end

  # 新規セッション作成
  # billing_model はサーバー側で決定（クライアントからの入力を無視）
  subscription = UserPlanSubscription.find_by(person: current_user, listing: listing)
  billing_model = subscription.present? ? 'subscription_with_overage' : 'token_based'

  session = ChatSession.create!(
    person: current_user,
    listing: listing,
    billing_model: billing_model,
    status: 'active'
  )

  render json: session, status: :created
end

private

def purchased?(person, listing)
  UserPlanSubscription.exists?(
    person: person,
    listing: listing,
    status: 'active'
  )
end

def verify_purchase
  # before_action として使用
end
```

**受け入れ条件**:
- [ ] 未購入ユーザーはチャットセッションを作成できない（403）
- [ ] 購入済みユーザーはチャットセッションを作成できる
- [ ] 既にセッションがある場合は既存セッションを返す
- [ ] `billing_model` はサーバー側で決定される

---

### タスク 3: 手動ウォレットトップアップ API

**目的**: ユーザーが Wallet に資金を追加できる API を提供する

**対象ファイル**:
- `app/controllers/api/v1/wallet_topup_controller.rb`（新規作成）
- `config/routes.rb`（ルート追加）

**実装仕様**:

```ruby
# app/controllers/api/v1/wallet_topup_controller.rb
module API
  module V1
    class WalletTopupController < BaseController
      def create
        amount_cents = params[:amount_cents].to_i

        # 金額のバリデーション
        if amount_cents < 100 || amount_cents > 100_00
          render json: { error: '金額は100円〜10,000円の間で指定してください' },
                 status: :unprocessable_entity
          return
        end

        wallet = current_user.wallet || Wallet.create!(person: current_user, balance_cents: 0)

        # Stripe PaymentIntent を作成
        intent = Stripe::PaymentIntent.create(
          amount: amount_cents,
          currency: 'jpy',
          customer: current_user.stripe_customer_id,
          metadata: {
            user_id: current_user.id,
            wallet_id: wallet.id,
            type: 'wallet_topup'
          }
        )

        render json: {
          client_secret: intent.client_secret,
          amount_cents: amount_cents
        }
      end

      def confirm
        # PaymentIntent 完了後の確認
        intent_id = params[:payment_intent_id]
        intent = Stripe::PaymentIntent.retrieve(intent_id)

        if intent.status == 'succeeded'
          wallet = Wallet.find(intent.metadata['wallet_id'])
          wallet.topup!(
            amount_cents: intent.amount,
            source: 'manual_topup'
          )
          render json: { status: 'ok', balance_cents: wallet.balance_cents }
        else
          render json: { error: '決済が完了していません' }, status: :unprocessable_entity
        end
      end
    end
  end
end
```

**ルート追加**:

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :wallet_topup, only: [:create] do
      post :confirm, on: :collection
    end
  end
end
```

**受け入れ条件**:
- [ ] `POST /api/v1/wallet_topup` で Stripe PaymentIntent が作成される
- [ ] `POST /api/v1/wallet_topup/confirm` で Wallet にトークンが追加される
- [ ] 金額バリデーション（100円〜10,000円）が機能する
- [ ] CreditTransaction（topup）が作成される

---

### タスク 4: ウォレットトップアップ UI

**目的**: チャット画面に残高表示とトップアップボタンを追加

**対象ファイル**:
- `client/app/startup/ChatPanelApp.js`
- `client/app/components/ChatPanel/wallet-topup.css`（新規作成）

**実装仕様**:

```jsx
// ChatPanelApp.js に追加するコンポーネント
class WalletBalance extends React.Component {
  constructor(props) {
    super(props);
    this.state = { balance: 0, showTopup: false };
  }

  render() {
    const { balance, showTopup } = this.state;
    return (
      <div className="wallet-balance">
        <span className="balance-label">残高:</span>
        <span className="balance-amount">¥{balance.toLocaleString()}</span>
        <button
          className="topup-button"
          onClick={() => this.setState({ showTopup: true })}
        >
          追加する
        </button>
        {showTopup && <WalletTopupModal onClose={() => this.setState({ showTopup: false })} />}
      </div>
    );
  }
}
```

**受け入れ条件**:
- [ ] チャット画面に現在の残高が表示される
- [ ] 「追加する」ボタンでトップアップモーダルが開く
- [ ] トップアップ完了後に残高が更新される
- [ ] 残高不足時にエラーメッセージにトップアップボタンが表示される

---

### タスク 5: 残高不足時のトップアップ誘導

**目的**: 残高不足エラー時にトップアップを促す

**対象ファイル**:
- `app/jobs/persona_executor_job.rb`
- `client/app/startup/ChatPanelApp.js`

**実装仕様**:

```ruby
# persona_executor_job.rb
# stream_error イベントに error_type を追加
broadcast_to_channel('stream_error', {
  error: 'トークンが不足しています。ウォレットをチャージしてください。',
  error_type: 'insufficient_balance',
  current_balance: wallet.balance_cents,
  topup_url: '/wallet/topup'
})
```

```javascript
// ChatPanelApp.js
handleError(data) {
  this.streamingId = null;
  if (data.error_type === 'insufficient_balance') {
    // トップアップボタン付きのエラーメッセージを表示
    this.addMessage('sys-err-' + Date.now(), 'system',
      `${data.error}`, false, { showTopupButton: true });
  } else {
    this.addMessage('sys-err-' + Date.now(), 'system',
      data.error || 'An error occurred.', false);
  }
}
```

**受け入れ条件**:
- [ ] 残高不足時に `error_type: "insufficient_balance"` が送信される
- [ ] フロントエンドでトップアップボタンが表示される
- [ ] トップアップボタンクリックでトップアップモーダルが開く

---

## 4. 実装順序

```
Phase A: バックエンド基盤（1-2日）
├── タスク 1: 購入→サブスクリプション連携
├── タスク 2: チャット購入検証
└── タスク 3: 手動ウォレットトップアップ API

Phase B: フロントエンド（1日）
├── タスク 4: ウォレットトップアップ UI
└── タスク 5: 残高不足時のトップアップ誘導

Phase C: テスト・検証（1日）
├── E2E テスト: 購入→チャット→残高不足→トップアップ→再チャット
└── エッジケース: 二重購入、決済失敗、月次上限
```

---

## 5. テストケース

### 正常系

| # | テストケース | 期待結果 |
|---|------------|---------|
| 1 | ペルソナを購入する | UserPlanSubscription が作成され、Wallet にトークンが付与される |
| 2 | 購入済みペルソナとチャットする | チャットセッションが作成され、AI レスポンスが返される |
| 3 | 残高不足時にトップアップする | Wallet にトークンが追加され、チャットが再開できる |
| 4 | 自動リチャージが有効な場合 | 残高低下時に自動でトークンが追加される |

### 異常系

| # | テストケース | 期待結果 |
|---|------------|---------|
| 5 | 未購入ユーザーがチャットを試みる | 403 エラーが返される |
| 6 | 決済が失敗した場合 | Transaction が作成されず、サブスクリプションも作成されない |
| 7 | 月次上限に達した場合 | 自動リチャージがスキップされる |
| 8 | 二重購入を試みる | 既存サブスクリプションが返される |

### エッジケース

| # | テストケース | 期待結果 |
|---|------------|---------|
| 9 | チャット中に残高が0になる | 最後のメッセージは処理され、次のメッセージでエラーが返される |
| 10 | 同じユーザーが複数ペルソナを購入する | 各ペルソナに独立したサブスクリプションとウォレットがある |

---

## 6. 注意事項

- **React 16.1.1**: フックは使えない。必ずクラスコンポーネントで実装
- **API モジュール名**: `API`（`Api` ではない — `inflect.acronym 'API'`）
- **Wallet#topup!**: 引数は `amount_cents:` と `source:`（文字列）
- **Stripe**: 本番 API キーは DB の `payment_settings` に格納
- **billing_model**: サーバー側で決定。クライアントからの入力を信頼しない
- **Person#name()**: 引数が必須。`@person.name` はエラー。`given_name_or_username` を使う

---

## 7. Stripe 決済フロー仕様（調査結果反映）

### 7-1. 結論: ✅ 要件を満たせる

Stripe の **Checkout Sessions + PaymentIntent** パターンで、4つの要件をすべて実現できる。

| 要件 | 実現方法 | 判定 |
|------|---------|------|
| 1. ペルソナを定額で購入 | Checkout Session (mode: 'payment') | ✅ |
| 2. 購入と同時にサブスクリプション自動作成 | Webhook でアプリ側に UserPlanSubscription 作成 | ✅ |
| 3. 購入時に初回トークン付与 | Webhook 処理で Wallet.topup! を呼び出し | ✅ |
| 4. トークン追加購入 | Checkout Session でトークンパックを購入 | ✅ |

### 7-2. Stripe の製品・価格モデル

```
Product（製品）
  └── Price（価格）
        ├── 1回限り（one-time）: PaymentIntent で処理
        └── 繰り返し（recurring）: Subscription で処理
```

| オブジェクト | 説明 | 使用場面 |
|------------|------|---------|
| **Product** | 販売する商品・サービスの定義 | ペルソナ自体 |
| **Price** | Product の価格設定 | 定額購入価格、トークン単価 |
| **Customer** | 顧客情報 | ユーザーの Stripe アカウント |
| **PaymentIntent** | 1回限りの決済 | ペルソナ購入、トークン追加購入 |
| **Checkout Session** | ホスト型決済ページ | ユーザーへの決済UI提示 |

### 7-3. 推奨アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  ユーザーインターフェース                                      │
│  ├─ ペルソナ購入ページ                                         │
│  ├─ ウォレットページ                                          │
│  └─ Stripe Customer Portal                                  │
├─────────────────────────────────────────────────────────────┤
│  Stripe Checkout Sessions                                    │
│  ├─ mode: 'payment' (1回限り決済)                            │
│  └─ payment_intent_data.metadata で種別を識別                 │
├─────────────────────────────────────────────────────────────┤
│  Webhook Handler                                             │
│  ├─ checkout.session.completed                              │
│  ├─ payment_intent.succeeded                                │
│  └─ payment_intent.payment_failed                           │
├─────────────────────────────────────────────────────────────┤
│  アプリケーションロジック                                       │
│  ├─ UserPlanSubscription 作成・管理                          │
│  ├─ Wallet.topup! / deduct_for_usage!                       │
│  └─ BillingService による使用量課金                           │
├─────────────────────────────────────────────────────────────┤
│  Stripe API                                                  │
│  ├─ Customer 作成・管理                                      │
│  ├─ Checkout Session 作成                                   │
│  ├─ PaymentIntent 作成                                      │
│  └─ Billing Portal Session 作成                             │
└─────────────────────────────────────────────────────────────┘
```

### 7-4. フロー詳細

#### ペルソナ購入フロー

```
ユーザーがペルソナを購入
       │
       ▼
1. Stripe Customer 作成（既存なら取得）
       │
       ▼
2. Checkout Session 作成（mode: 'payment'）
   ├─ line_items: [{ price: persona_price_id, quantity: 1 }]
   └─ payment_intent_data: { metadata: { persona_id, user_id } }
       │
       ▼
3. Webhook で `checkout.session.completed` 受信
       │
       ▼
4. アプリケーション側で処理：
   ├─ UserPlanSubscription 作成（billing_model: 'token_credit'）
   ├─ Wallet に初回トークン付与
   └─ Stripe Customer ID を StripeAccount に保存
```

#### トークン追加購入フロー

```
トークンがなくなる
       │
       ▼
1. Checkout Session 作成（mode: 'payment'）
   ├─ line_items: [{ price: token_pack_price_id, quantity: 1 }]
   └─ payment_intent_data: { metadata: { type: 'token_topup', user_id } }
       │
       ▼
2. Webhook で `checkout.session.completed` 受信
       │
       ▼
3. Wallet.topup! でトークン付与
```

### 7-5. 既存コードとの整合性

| 項目 | 現状 | 改善必要 |
|------|------|---------|
| **StripeAccount** | `stripe_customer_id` カラムあり | ✅ そのまま使用可能 |
| **Wallet** | `topup!` メソッド実装済み | ✅ そのまま使用可能 |
| **UserPlanSubscription** | `stripe_subscription_id` カラムあり | ✅ 1回限り決済では nil を設定 |
| **Stripe API Wrapper** | `StripeAPIWrapper` クラス実装済み | ⚠️ Checkout Session 対応を追加必要 |

### 7-6. 追加実装が必要なコンポーネント

| コンポーネント | 説明 | 優先度 |
|---------------|------|:------:|
| **StripeCheckoutService** | Checkout Session 作成ロジック | 🔴 高 |
| **StripeWebhooksController** | Webhook 処理（`checkout.session.completed` 対応） | 🔴 高 |
| **Listing に `stripe_price_id` カラム追加** | 各ペルソナの Stripe Price ID | 🔴 高 |
| **BillingConfig に `initial_token_credit` 設定追加** | 初回付与トークン数 | 🔴 高 |
| **ルーティング設定** | 購入・ウォレット・ポータル用ルート | 🟡 中 |

### 7-7. 実装コード例

#### StripeCheckoutService

```ruby
# app/services/stripe_checkout_service.rb
class StripeCheckoutService
  STRIPE_API_VERSION = '2024-12-18.acacia'

  def initialize(person:, community:)
    @person = person
    @community = community
    configure_stripe
  end

  # ペルソナ購入用の Checkout Session を作成
  def create_persona_purchase_session(listing)
    customer = ensure_stripe_customer
    price_id = listing.stripe_price_id

    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      line_items: [{ price: price_id, quantity: 1 }],
      mode: 'payment',
      success_url: success_url(listing),
      cancel_url: cancel_url(listing),
      payment_intent_data: {
        metadata: {
          type: 'persona_purchase',
          persona_id: listing.id,
          user_id: @person.id,
          community_id: @community.id
        }
      }
    )

    session.url
  end

  # トークン追加購入用の Checkout Session を作成
  def create_token_topup_session(amount_cents:, tokens:)
    customer = ensure_stripe_customer

    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      line_items: [{
        price_data: {
          currency: 'jpy',
          product_data: {
            name: "#{tokens} トークン",
            description: "AI チャット用クレジット"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      mode: 'payment',
      success_url: token_success_url,
      cancel_url: token_cancel_url,
      payment_intent_data: {
        metadata: {
          type: 'token_topup',
          tokens: tokens,
          user_id: @person.id,
          community_id: @community.id
        }
      }
    )

    session.url
  end

  private

  def configure_stripe
    Stripe.api_key = retrieve_stripe_secret_key
    Stripe.api_version = STRIPE_API_VERSION
  end

  def ensure_stripe_customer
    stripe_account = @person.stripe_account
    if stripe_account&.stripe_customer_id.present?
      Stripe::Customer.retrieve(stripe_account.stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email: @person.emails.first&.address,
        metadata: { person_id: @person.id, community_id: @community.id }
      )
      if stripe_account
        stripe_account.update!(stripe_customer_id: customer.id)
      else
        StripeAccount.create!(
          person_id: @person.id,
          community_id: @community.id,
          stripe_customer_id: customer.id
        )
      end
      customer
    end
  end

  def retrieve_stripe_secret_key
    payment_settings = PaymentSettings.find_by(
      community_id: @community.id,
      payment_gateway: :stripe,
      active: true
    )
    TransactionService::Store::PaymentSettings.decrypt_value(
      payment_settings.api_private_key,
      payment_settings.key_encryption_padding
    )
  end
end
```

#### StripeWebhooksController

```ruby
# app/controllers/stripe_webhooks_controller.rb
class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_stripe_webhook

  def create
    event = @payload

    case event['type']
    when 'checkout.session.completed'
      handle_checkout_completed(event['data']['object'])
    when 'payment_intent.succeeded'
      handle_payment_succeeded(event['data']['object'])
    when 'payment_intent.payment_failed'
      handle_payment_failed(event['data']['object'])
    else
      Rails.logger.info("[StripeWebhook] Unhandled: #{event['type']}")
    end

    head :ok
  end

  private

  def verify_stripe_webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    begin
      @payload = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error("[StripeWebhook] Verification failed: #{e.message}")
      head :bad_request
    end
  end

  def handle_checkout_completed(session)
    metadata = session['metadata'] || {}

    case metadata['type']
    when 'persona_purchase'
      process_persona_purchase(session, metadata)
    when 'token_topup'
      process_token_topup(session, metadata)
    end
  end

  def process_persona_purchase(session, metadata)
    person = Person.find(metadata['user_id'])
    listing = Listing.find(metadata['persona_id'])

    ActiveRecord::Base.transaction do
      # 1. UserPlanSubscription を作成
      UserPlanSubscription.create!(
        person_id: person.id,
        listing_id: listing.id,
        billing_model: 'token_credit',
        status: 'active',
        current_period_start: Time.current,
        current_period_end: 1.year.from_now,
        stripe_subscription_id: nil  # 1回限り決済のため nil
      )

      # 2. Wallet に初回トークンを付与
      wallet = Wallet.find_or_create_by!(person_id: person.id)
      initial_tokens = BillingConfig.new(listing: listing).included_tokens
      wallet.topup!(
        amount_cents: initial_tokens * BillingConfig.per_token_price_cents,
        source: 'initial_purchase'
      )
    end
  end

  def process_token_topup(session, metadata)
    person = Person.find(metadata['user_id'])
    wallet = person.wallet
    tokens = metadata['tokens'].to_i

    if wallet
      wallet.topup!(
        amount_cents: tokens * BillingConfig.per_token_price_cents,
        source: 'manual_topup'
      )
    end
  end
end
```

### 7-8. 制限事項・注意点

| 制限 | 内容 | 対策 |
|------|------|------|
| **API レート制限** | 100 requests/second（連続） | idempotency_key の使用、キューイング |
| **Webhook 確認** | イベントの重複送信が発生する可能性 | idempotent な処理設計 |
| **Checkout Session** | 有効期限 24 時間 | ユーザーに期限を案内 |
| **Customer Portal** | カスタマイズに制限あり | カスタム UI の併用 |

### 7-9. ルーティング設定

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Stripe Webhook
  post '/stripe/webhook', to: 'stripe_webhooks#create'

  # ペルソナ購入
  resources :listings do
    member do
      post :purchase
      get 'purchase/success', to: 'purchases#success'
      get 'purchase/cancel', to: 'purchases#cancel'
    end
  end

  # ウォレット
  resource :wallet do
    post :topup
    get 'topup/success', to: 'wallets#topup_success'
    get 'topup/cancel', to: 'wallets#topup_cancel'
  end

  # Stripe Customer Portal
  get '/account/billing', to: 'billing#show'
  post '/account/billing/portal', to: 'billing#create_portal'
end
```
