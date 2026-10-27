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

  describe "POST /webhooks/freemius payment.created (fixed prepaid, Issue #46)" do
    let(:buyer_email) { person.emails.first.address }

    before do
      allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_return({ "5678" => 1000, "5679" => 3000 }.to_json)
      allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return("0.0067")
    end

    def fixed_payload(payment_id: "fs_topup_1", plan_id: "5678", email: nil, metadata: {})
      {
        event: "payment.created",
        objects: {
          payment: {
            id: payment_id,
            plan_id: plan_id,
            gross: 5.0,
            currency: "usd",
            user_email: email,
            metadata: metadata
          },
          user: email ? { email: email } : {}
        }
      }
    end

    it "credits the map amount (not gross) via plan_id + user_email exact match" do
      allow(FreemiusClient).to receive(:get_payment).with("fs_topup_1").and_return(
        { "id" => "fs_topup_1", "gross" => 5.0, "currency" => "usd" }
      )
      payload = fixed_payload(email: buyer_email)
      expect { signed_post(payload) }
        .to change { wallet.reload.balance_cents }.from(0).to(1000)
      expect(response).to have_http_status(200)
      tx = wallet.credit_transactions.where(transaction_type: "topup").last
      expect(tx.metadata).to include("fs_topup_1")
    end

    it "matches email case-insensitively but exactly (no prefix confusion)" do
      allow(FreemiusClient).to receive(:get_payment).with("fs_topup_1").and_return(
        { "id" => "fs_topup_1", "gross" => 5.0, "currency" => "usd" }
      )
      # Uppercase should still match (stored lowercase); prefix must not.
      expect { signed_post(fixed_payload(email: buyer_email.upcase)) }
        .to change { wallet.reload.balance_cents }.from(0).to(1000)
      other = FactoryBot.create(:person, community_id: community.id)
      other_wallet = FactoryBot.create(:wallet, person: other, community: community, balance_cents: 0)
      evil = "x" + buyer_email
      allow(FreemiusClient).to receive(:get_payment).with("fs_topup_2").and_return(
        { "id" => "fs_topup_2", "gross" => 5.0, "currency" => "usd" }
      )
      expect { signed_post(fixed_payload(payment_id: "fs_topup_2", email: evil)) }
        .not_to(change { wallet.reload.balance_cents })
      expect(other_wallet.reload.balance_cents).to eq(0)
    end

    it "skips unknown plan_id without credit (no mis-credit)" do
      allow(FreemiusClient).to receive(:get_payment).and_return(
        { "id" => "fs_topup_x", "gross" => 5.0, "currency" => "usd" }
      )
      expect { signed_post(fixed_payload(payment_id: "fs_topup_x", plan_id: "9999", email: buyer_email)) }
        .not_to(change { wallet.reload.balance_cents })
      expect(response).to have_http_status(200)
    end

    it "is idempotent on duplicate delivery (freemius:<id> exact)" do
      allow(FreemiusClient).to receive(:get_payment).with("fs_topup_1").and_return(
        { "id" => "fs_topup_1", "gross" => 5.0, "currency" => "usd" }
      )
      payload = fixed_payload(email: buyer_email)
      signed_post(payload)
      expect { signed_post(payload) }.not_to(change { wallet.reload.balance_cents })
    end

    it "does not confuse fs_topup_1 with fs_topup_10" do
      wallet.topup!(100, freemius_payment_id: "fs_topup_10")
      allow(FreemiusClient).to receive(:get_payment).with("fs_topup_1").and_return(
        { "id" => "fs_topup_1", "gross" => 5.0, "currency" => "usd" }
      )
      expect { signed_post(fixed_payload(email: buyer_email)) }
        .to change { wallet.reload.balance_cents }.from(100).to(1100)
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

  describe "POST /webhooks/freemius API failure is auxiliary (Issue #43 completion)" do
    it "fixed prepaid: API failureでも署名正なら map 額を加算する" do
      allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_return({ "5678" => 1000 }.to_json)
      allow(FreemiusClient).to receive(:get_payment).with("fs_topup_aux")
        .and_raise(FreemiusClient::ApiError.new("Freemius API error (503): unavailable"))
      payload = {
        event: "payment.created",
        objects: {
          payment: { id: "fs_topup_aux", plan_id: "5678", gross: 5.0, metadata: { user_id: person.id } }
        }
      }
      expect { signed_post(payload) }.to change { wallet.reload.balance_cents }.from(0).to(1000)
      expect(response).to have_http_status(200)
    end

    it "legacy wallet (plan なし): API failureでは金額不明のため加算しない" do
      allow(FreemiusClient).to receive(:get_payment).with("fs_pay_legacy")
        .and_raise(FreemiusClient::ApiError.new("Freemius API error (401): unauthorized"))
      payload = {
        event: "payment.created",
        objects: {
          payment: { id: "fs_pay_legacy", gross: 30.0, metadata: { user_id: person.id, wallet_id: wallet.id } }
        }
      }
      expect { signed_post(payload) }.not_to(change { wallet.reload.balance_cents })
      expect(response).to have_http_status(200)
    end
  end

  describe "POST /webhooks/freemius subscription.canceled alias" do
    let!(:subscription) do
      FactoryBot.create(:user_plan_subscription,
                        person: person,
                        listing: FactoryBot.create(:listing, community_id: community.id, author: person),
                        billing_model: "subscription",
                        freemius_subscription_id: "fs_sub_2")
    end

    it "handles subscription.canceled (US spelling) via the state machine" do
      payload = {
        event: "subscription.canceled",
        objects: { subscription: { id: "fs_sub_2" } }
      }
      signed_post(payload)
      expect(response).to have_http_status(200)
      expect(subscription.reload.current_state).to eq("canceled")
    end
  end

  describe "POST /webhooks/freemius 実配信の payload 形（トップレベル type）" do
    before do
      allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_return({ "74358" => 600 }.to_json)
      allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return("0.0065")
    end

    # 実測（2026-10-24 の実決済）の payload は `event.type` ではなく
    # トップレベルの `type` でイベント種別を送ってくる。ここが拾えないと
    # 「DB アクセスなしの 200」で黙って無視される。
    let(:real_payload) do
      {
        type: "payment.created",
        plugin_id: "41567",
        user_id: "10602734",
        data: { payment_id: "2177322", license_id: "2079147" },
        objects: {
          user: { id: "10602734", email: person.emails.first.address },
          payment: {
            id: "2177322",
            plan_id: "74358",
            user_id: "10602734",
            gross: 5,
            currency: "usd",
            type: "payment",
            environment: 0
          }
        },
        is_live: true
      }
    end

    it "トップレベル type でもチャージを付与する" do
      allow(FreemiusClient).to receive(:get_payment).with("2177322").and_return(
        { "id" => "2177322", "gross" => 5.0, "currency" => "usd" }
      )

      expect { signed_post(real_payload) }
        .to change { wallet.reload.balance_cents }.from(0).to(600)
      expect(response).to have_http_status(200)
    end

    it "再送しても二重加算しない" do
      allow(FreemiusClient).to receive(:get_payment).with("2177322").and_return(
        { "id" => "2177322", "gross" => 5.0, "currency" => "usd" }
      )

      signed_post(real_payload)
      expect { signed_post(real_payload) }
        .not_to(change { wallet.reload.balance_cents })
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
