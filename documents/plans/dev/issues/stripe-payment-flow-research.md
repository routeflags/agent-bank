# Stripe 決済フロー調査レポート

## 優先度
🔴 高

## 調査目的
Stripe を使った決済フローで、以下の要件を満たせるか調査する：
1. ユーザーがペルソナを定額で購入する（1回限りの決済）
2. 購入と同時にサブスクリプション（UserPlanSubscription）を自動作成する
3. 購入時に初回トークン（クレジット）を付与する
4. トークンがなくなった場合、追加でチャットするためのトークンクレジットを購入する

## 調査方法
- コードベース検索: `grep`, `serena`
- 参照ドキュメント: [Stripe 公式ドキュメント](https://docs.stripe.com)
- 検証コード: `app/services/billing_service.rb`, `app/models/wallet.rb`

## 結果

### 1. Stripe の製品・価格モデルの説明

Stripe の製品・価格モデルは以下の階層構造を持つ：

```
Product（製品）
  └── Price（価格）
        ├── 1回限り（one-time）: PaymentIntent で処理
        └── 繰り返し（recurring）: Subscription で処理
```

**主な概念：**

| オブジェクト | 説明 | 使用場面 |
|------------|------|---------|
| **Product** | 販売する商品・サービスの定義 | ペルソナ自体 |
| **Price** | Product の価格設定 | 定額購入価格、トークン単価 |
| **Customer** | 顧客情報 | ユーザーの Stripe アカウント |
| **PaymentIntent** | 1回限りの決済 | ペルソナ購入、トークン追加購入 |
| **Subscription** | 定期課金 | ペルソナ使用権の管理 |
| **Checkout Session** | ホスト型決済ページ | ユーザーへの決済UI提示 |

### 2. 推奨実装パターン

#### パターンA: Checkout Sessions + PaymentIntent（推奨）

**1回限り決済 + サブスクリプション管理の組み合わせ：**

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

**トークン追加購入フロー：**

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

#### パターンB: Stripe Customer Portal（補助）

- ユーザーが自己的な情報を管理するためのホスト型ポータル
- サブスクリプションの確認・キャンセルが可能
- カスタマーポータルの URL を提供

### 3. 実装コード例

#### 3.1 Stripe サービスの作成

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
  #
  # @param listing [Listing] 購入対象のペルソナ
  # @return [String] Checkout Session の URL
  def create_persona_purchase_session(listing)
    customer = ensure_stripe_customer
    price_id = listing.stripe_price_id # Listing に stripe_price_id カラムを追加

    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      line_items: [{
        price: price_id,
        quantity: 1
      }],
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
      },
      metadata: {
        type: 'persona_purchase',
        persona_id: listing.id,
        user_id: @person.id
      }
    )

    session.url
  end

  # トークン追加購入用の Checkout Session を作成
  #
  # @param amount_cents [Integer] 購入金額（セント）
  # @param tokens [Integer] 購入トークン数
  # @return [String] Checkout Session の URL
  def create_token_topup_session(amount_cents:, tokens:)
    customer = ensure_stripe_customer

    # トークンパック用の Price を動的に作成（または事前作成済みの Price を使用）
    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: "#{tokens} tokens",
            description: "Token credit for AI chat"
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
      },
      metadata: {
        type: 'token_topup',
        tokens: tokens,
        user_id: @person.id
      }
    )

    session.url
  end

  # Customer Portal セッションを作成（ユーザーが購入履歴を確認）
  #
  # @return [String] Portal の URL
  def create_portal_session
    customer = ensure_stripe_customer

    portal_session = Stripe::BillingPortal::Session.create(
      customer: customer.id,
      return_url: portal_return_url
    )

    portal_session.url
  end

  private

  def configure_stripe
    Stripe.api_key = retrieve_stripe_secret_key
    Stripe.api_version = STRIPE_API_VERSION
  end

  # Stripe Customer を取得 or 作成
  def ensure_stripe_customer
    stripe_account = @person.stripe_account

    if stripe_account&.stripe_customer_id.present?
      Stripe::Customer.retrieve(stripe_account.stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email: @person.emails.first&.address,
        metadata: {
          person_id: @person.id,
          community_id: @community.id
        }
      )

      # StripeAccount に customer_id を保存
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

  def success_url(listing)
    "#{app_base_url}/listings/#{listing.id}/purchase/success"
  end

  def cancel_url(listing)
    "#{app_base_url}/listings/#{listing.id}/purchase/cancel"
  end

  def token_success_url
    "#{app_base_url}/wallet/topup/success"
  end

  def token_cancel_url
    "#{app_base_url}/wallet/topup/cancel"
  end

  def portal_return_url
    "#{app_base_url}/account/billing"
  end

  def app_base_url
    @community.full_domain || "https://#{@community.ident}.sharetribe.com"
  end
end
```

#### 3.2 Webhook コントローラー

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
    when 'customer.subscription.created'
      handle_subscription_created(event['data']['object'])
    when 'customer.subscription.updated'
      handle_subscription_updated(event['data']['object'])
    when 'customer.subscription.deleted'
      handle_subscription_deleted(event['data']['object'])
    else
      Rails.logger.info("[StripeWebhook] Unhandled event type: #{event['type']}")
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
    rescue JSON::ParserError => e
      Rails.logger.error("[StripeWebhook] Invalid payload: #{e.message}")
      head :bad_request
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("[StripeWebhook] Invalid signature: #{e.message}")
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
    else
      Rails.logger.warn("[StripeWebhook] Unknown checkout type: #{metadata['type']}")
    end
  end

  def process_persona_purchase(session, metadata)
    person_id = metadata['user_id']
    listing_id = metadata['persona_id']
    community_id = metadata['community_id']

    person = Person.find(person_id)
    listing = Listing.find(listing_id)
    community = Community.find(community_id)

    ActiveRecord::Base.transaction do
      # 1. UserPlanSubscription を作成
      subscription = UserPlanSubscription.create!(
        person_id: person_id,
        listing_id: listing_id,
        billing_model: 'token_credit', # カスタムモデル
        status: 'active',
        current_period_start: Time.current,
        current_period_end: 1.year.from_now, # 1年間有効
        stripe_subscription_id: nil # 1回限り決済のため nil
      )

      # 2. Wallet を作成 or 取得
      wallet = Wallet.find_or_create_by!(
        person_id: person_id,
        community_id: community_id
      )

      # 3. 初回トークンを付与（例: 10,000トークン）
      initial_tokens = BillingConfig.initial_token_credit
      wallet.topup!(initial_tokens, stripe_payment_id: session['payment_intent'])

      Rails.logger.info("[StripeWebhook] Persona purchase completed: person=#{person_id}, listing=#{listing_id}, tokens=#{initial_tokens}")
    end
  end

  def process_token_topup(session, metadata)
    person_id = metadata['user_id']
    tokens = metadata['tokens'].to_i

    person = Person.find(person_id)
    wallet = person.wallet

    if wallet
      wallet.topup!(tokens, stripe_payment_id: session['payment_intent'])
      Rails.logger.info("[StripeWebhook] Token topup completed: person=#{person_id}, tokens=#{tokens}")
    else
      Rails.logger.error("[StripeWebhook] Wallet not found for person: #{person_id}")
    end
  end

  def handle_payment_succeeded(payment_intent)
    Rails.logger.info("[StripeWebhook] Payment succeeded: #{payment_intent['id']}")
    # 必要に応じて追加処理
  end

  def handle_payment_failed(payment_intent)
    Rails.logger.warn("[StripeWebhook] Payment failed: #{payment_intent['id']}")
    # 失敗通知の送信等
  end

  def handle_subscription_created(subscription)
    Rails.logger.info("[StripeWebhook] Subscription created: #{subscription['id']}")
    # サブスクリプション関連の処理
  end

  def handle_subscription_updated(subscription)
    Rails.logger.info("[StripeWebhook] Subscription updated: #{subscription['id']}")
    # ステータス変更の同期
  end

  def handle_subscription_deleted(subscription)
    Rails.logger.info("[StripeWebhook] Subscription deleted: #{subscription['id']}")
    # サブスクリプションキャンセル処理
  end
end
```

#### 3.3 ルーティング設定

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

### 4. 制限事項・注意点

#### Stripe の制限事項

| 制限 | 内容 | 対策 |
|------|------|------|
| **API レート制限** | 100 requests/second（連続） | idempotency_key の使用、キューイング |
| **Webhook 確認** | イベントの重複送信が発生する可能性 | idempotent な処理設計 |
| **Checkout Session** | 有効期限 24 時間 | ユーザーに期限を案内 |
| **Customer Portal** | カスタマイズに制限あり | カスタム UI の併用 |

#### 実装上の注意点

| 項目 | 注意点 |
|------|--------|
| **Webhook セキュリティ** | 署名の検証を必ず実装する |
| **エラーハンドリング** | Stripe エラーを適切にキャッチし、ユーザーに通知する |
| **冪等性** | Webhook 処理は冪等にする（重複処理を防ぐ） |
| **テスト** | Stripe の テストモードで十分に検証する |
| **监控** | 決済失敗や webhook エラーを監控する |

#### 既存コードベースとの整合性

| 項目 | 現状 | 改善必要 |
|------|------|---------|
| **StripeAccount** | `stripe_customer_id` カラムあり | ✅ そのまま使用可能 |
| **Wallet** | `topup!` メソッド実装済み | ✅ そのまま使用可能 |
| **UserPlanSubscription** | `stripe_subscription_id` カラムあり | ✅ 1回限り決済では nil を設定 |
| **Stripe API Wrapper** | `StripeAPIWrapper` クラス実装済み | ⚠️ Checkout Session 対応を追加必要 |

### 5. 結論

**要件を満たせるかどうかの判断：✅ 可能**

Stripe の Checkout Sessions + PaymentIntent パターンを使用することで、以下の要件をすべて満たすことができる：

| 要件 | 実現方法 | 判定 |
|------|---------|------|
| 1. ユーザーがペルソナを定額で購入 | Checkout Session (mode: 'payment') | ✅ |
| 2. 購入と同時にサブスクリプションを自動作成 | Webhook でアプリケーション側に UserPlanSubscription 作成 | ✅ |
| 3. 購入時に初回トークンを付与 | Webhook 処理で Wallet.topup! を呼び出し | ✅ |
| 4. トークンがなくなった場合の追加購入 | Checkout Session でトークンパックを購入 | ✅ |

**推奨アーキテクチャ：**

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

**追加実装が必要なコンポーネント：**

1. **StripeCheckoutService** - Checkout Session 作成ロジック
2. **StripeWebhooksController** - Webhook 処理
3. **Listing に stripe_price_id カラム追加** - 各ペルソナの Stripe Price ID
4. **BillingConfig に initial_token_credit 設定追加** - 初回付与トークン数
5. **ルーティング設定** - 購入・ウォレット・ポータル用ルート

**既存のWallet.topup!メソッドはそのまま使用可能**で、追加実装は最小限で済む。

## 備考
- Stripe のテストモードで動作確認を推奨
- 本番環境への移行前に、セキュリティレビューを実施すること
- Webhook のエラーハンドリングと再試行ロジックを検討すること
