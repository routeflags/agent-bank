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
    allow(ENV).to receive(:[]).with("FREEMIUS_WEBHOOK_SECRET").and_return(secret)
  end

  describe "POST /webhooks/freemius payment.completed" do
    let(:payload) do
      {
        event: "payment.completed",
        objects: {
          payment: {
            id: "fs_pay_1",
            amount_cents: 3000,
            metadata: { user_id: person.id, wallet_id: wallet.id }
          }
        }
      }
    end

    before do
      # Server-side verification fetches the payment from Freemius.
      allow(FreemiusClient).to receive(:get_payment).with("fs_pay_1").and_return(
        { "id" => "fs_pay_1", "status" => "completed", "amount_cents" => 3000 }
      )
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

  describe "POST /webhooks/freemius payment.refunded" do
    before do
      wallet.topup!(3000, freemius_payment_id: "fs_pay_9")
    end

    it "records a reversing refund entry and decrements the balance" do
      payload = {
        event: "payment.refunded",
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
        event: "payment.refunded",
        objects: { payment: { id: "fs_pay_9" } }
      }
      signed_post(payload)
      expect { signed_post(payload) }
        .not_to(change {
          wallet.credit_transactions.where(transaction_type: "refund").count
        })
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
