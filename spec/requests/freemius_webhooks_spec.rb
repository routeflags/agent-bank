# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "FreemiusWebhooks", type: :request do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 0) }
  let(:secret) { "test_webhook_secret" }

  def signed_post(payload)
    raw = payload.to_json
    sig = OpenSSL::HMAC.hexdigest("SHA256", secret, raw)
    post "/webhooks/freemius",
         params: raw,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_X_SIGNATURE" => sig
         }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PRODUCT_SECRET_KEY").and_return(secret)
    allow(ENV).to receive(:[]).with("FREEMIUS_WEBHOOK_SECRET").and_return(nil)
  end

  describe "POST /webhooks/freemius payment.created (real event)" do
    let(:payload) do
      {
        event: "payment.created",
        objects: {
          payment: {
            id: "fs_pay_1",
            gross: 30.0,
            currency: "usd",
            metadata: { user_id: person.id, wallet_id: wallet.id }
          }
        }
      }
    end

    let(:payload_created) do
      {
        event: { type: "payment.created" },
        objects: {
          payment: {
            id: "fs_pay_1",
            gross: 30.0,
            currency: "usd",
            metadata: { user_id: person.id, wallet_id: wallet.id }
          }
        }
      }
    end

    before do
      # Server-side verification fetches the payment from Freemius (real schema: gross).
      allow(FreemiusClient).to receive(:get_payment).with("fs_pay_1").and_return(
        { "id" => "fs_pay_1", "gross" => 30.0, "currency" => "usd" }
      )
    end

    it "accepts the object-form event type" do
      expect { signed_post(payload_created) }
        .to change { wallet.reload.balance_cents }.from(0).to(3000)
      expect(response).to have_http_status(200)
    end

    it "credits the wallet" do
      expect { signed_post(payload) }
        .to change { wallet.reload.balance_cents }.from(0).to(3000)
      expect(response).to have_http_status(200)
    end

    it "is idempotent on duplicate delivery" do
      signed_post(payload)
      expect { signed_post(payload) }
        .not_to(change { wallet.reload.balance_cents })
      expect(response).to have_http_status(200)
    end

    it "records the freemius payment id in metadata" do
      signed_post(payload)
      tx = wallet.credit_transactions.where(transaction_type: "topup").last
      expect(tx.metadata).to include("fs_pay_1")
    end

    it "skips credit when the payment is not completed remotely" do
      allow(FreemiusClient).to receive(:get_payment).with("fs_pay_1").and_return(
        { "id" => "fs_pay_1", "status" => "pending", "amount_cents" => 3000 }
      )
      expect { signed_post(payload) }
        .not_to(change { wallet.reload.balance_cents })
      expect(response).to have_http_status(200)
    end

    it "does not confuse fs_pay_1 with fs_pay_10 (exact match)" do
      wallet.topup!(100, freemius_payment_id: "fs_pay_10")
      expect { signed_post(payload) }
        .to change { wallet.reload.balance_cents }.from(100).to(3100)
    end
  end

  describe "POST /webhooks/freemius payment.created (persona_purchase, real event)" do
    let(:author) { FactoryBot.create(:person, community_id: community.id) }
    let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: author) }
    let(:initial_grant_cents) do
      BillingConfig.included_tokens(:subscription) * BillingConfig.per_token_price_cents(:subscription)
    end
    let(:payload) do
      {
        event: "payment.created",
        objects: {
          payment: {
            id: "fs_pay_p1",
            gross: 30.0,
            currency: "usd",
            metadata: { type: "persona_purchase", user_id: person.id, listing_id: listing.id }
          }
        }
      }
    end

    before do
      allow(FreemiusClient).to receive(:get_payment).with("fs_pay_p1").and_return(
        { "id" => "fs_pay_p1", "gross" => 30.0, "currency" => "usd" }
      )
    end

    it "購入権利（UserPlanSubscription）を作成する" do
      expect { signed_post(payload) }
        .to change(UserPlanSubscription, :count).by(1)

      expect(response).to have_http_status(200)
      sub = UserPlanSubscription.last
      expect(sub.person_id).to eq(person.id)
      expect(sub.listing_id).to eq(listing.id)
      expect(sub.status).to eq("active")
    end

    it "payment_reference に freemius:<payment_id> を記録し、初期トークンを付与する" do
      expect { signed_post(payload) }
        .to change { person.reload.wallet.balance_cents }.from(0).to(initial_grant_cents)

      tx = person.wallet.credit_transactions.where(transaction_type: "topup").last
      expect(tx.metadata).to include("freemius:fs_pay_p1")
    end

    it "ウォレットチャージ（wallet topup）として扱わない（決済額はチャージしない）" do
      signed_post(payload)

      # 付与されるのは初期トークンのみ。決済額 3000 はチャージされない
      expect(person.reload.wallet.balance_cents).to eq(initial_grant_cents)
      expect(person.wallet.balance_cents).not_to eq(3000)
    end

    it "同じ payment の再送で二重に付与しない（冪等）" do
      signed_post(payload)

      expect { signed_post(payload) }
        .not_to change(UserPlanSubscription, :count)
      expect(response).to have_http_status(200)
      expect(person.reload.wallet.balance_cents).to eq(initial_grant_cents)
    end

    it "旧名 payment.completed でも受理する（後方互換）" do
      legacy = {
        event: "payment.completed",
        objects: {
          payment: {
            id: "fs_pay_p1",
            gross: 30.0,
            metadata: { type: "persona_purchase", user_id: person.id, listing_id: listing.id }
          }
        }
      }

      expect { signed_post(legacy) }
        .to change(UserPlanSubscription, :count).by(1)
      expect(response).to have_http_status(200)
    end

    it "リモートで completed でなければ購入権利を作成しない" do
      allow(FreemiusClient).to receive(:get_payment).with("fs_pay_p1").and_return(
        { "id" => "fs_pay_p1", "status" => "pending", "gross" => 30.0 }
      )

      expect { signed_post(payload) }
        .not_to change(UserPlanSubscription, :count)
      expect(response).to have_http_status(200)
    end

    it "listing が見つからない場合は 200 でスキップする（500 にしない）" do
      payload[:objects][:payment][:metadata][:listing_id] = -1

      expect { signed_post(payload) }
        .not_to change(UserPlanSubscription, :count)
      expect(response).to have_http_status(200)
    end

    it "person が見つからない場合は 200 でスキップする（500 にしない）" do
      payload[:objects][:payment][:metadata][:user_id] = "missing_person_id"

      expect { signed_post(payload) }
        .not_to change(UserPlanSubscription, :count)
      expect(response).to have_http_status(200)
    end

    it "metadata に listing_id が無い場合は 200 でスキップする" do
      payload[:objects][:payment][:metadata].delete(:listing_id)

      expect { signed_post(payload) }
        .not_to change(UserPlanSubscription, :count)
      expect(response).to have_http_status(200)
    end

    it "署名が不正なら 401 で、何も付与しない" do
      expect {
        post "/webhooks/freemius",
             params: payload.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_SIGNATURE" => "bad" }
      }.not_to change(UserPlanSubscription, :count)

      expect(response).to have_http_status(401)
    end
  end

  describe "POST /webhooks/freemius payment.refund (real event)" do
    before do
      wallet.topup!(3000, freemius_payment_id: "fs_pay_9")
    end

    it "records a reversing refund entry and decrements the balance" do
      payload = {
        event: "payment.refund",
        objects: { payment: { id: "fs_pay_9" } }
      }
      expect { signed_post(payload) }
        .to change {
          wallet.credit_transactions.where(transaction_type: "refund").count
        }.by(1)
      expect(response).to have_http_status(200)
      expect(wallet.reload.balance_cents).to eq(0)
    end

    it "does not double-reverse on duplicate delivery" do
      payload = {
        event: "payment.refund",
        objects: { payment: { id: "fs_pay_9" } }
      }
      signed_post(payload)
      expect { signed_post(payload) }
        .not_to(change {
          wallet.credit_transactions.where(transaction_type: "refund").count
        })
    end

    it "accepts legacy payment.refunded (backward compatibility)" do
      payload = {
        event: "payment.refunded",
        objects: { payment: { id: "fs_pay_9" } }
      }
      expect { signed_post(payload) }
        .to change {
          wallet.credit_transactions.where(transaction_type: "refund").count
        }.by(1)
      expect(response).to have_http_status(200)
    end
  end

  describe "POST /webhooks/freemius subscription events" do
    let!(:subscription) do
      FactoryBot.create(:user_plan_subscription,
                        person: person,
                        listing: FactoryBot.create(:listing, community_id: community.id, author: person),
                        billing_model: "subscription",
                        freemius_subscription_id: "fs_sub_1")
    end

    it "handles subscription.renewal.failed without error" do
      payload = {
        event: "subscription.renewal.failed",
        objects: { subscription: { id: "fs_sub_1" } }
      }
      signed_post(payload)
      expect(response).to have_http_status(200)
    end

    it "handles subscription.cancelled via the state machine" do
      payload = {
        event: "subscription.cancelled",
        objects: { subscription: { id: "fs_sub_1" } }
      }
      signed_post(payload)
      expect(response).to have_http_status(200)
      expect(subscription.reload.current_state).to eq("canceled")
    end

    it "handles subscription.cancelled from past_due" do
      subscription.transition_to!(:past_due)
      payload = {
        event: "subscription.cancelled",
        objects: { subscription: { id: "fs_sub_1" } }
      }
      signed_post(payload)
      expect(response).to have_http_status(200)
      expect(subscription.reload.current_state).to eq("canceled")
    end
  end

  describe "signature verification" do
    it "rejects requests with a bad signature" do
      post "/webhooks/freemius",
           params: { event: "payment.completed" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_SIGNATURE" => "bad" }
      expect(response).to have_http_status(401)
    end

    it "rejects requests without a signature" do
      post "/webhooks/freemius",
           params: { event: "payment.completed" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(401)
    end
  end
end
