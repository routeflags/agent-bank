# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FreemiusClient do
  let(:api_key) { "test_freemius_key" }

  before do
    stub_const("FreemiusClient::DEFAULT_BASE_URL", "https://api.freemius.test/v1")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FREEMIUS_API_KEY").and_return(api_key)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("FREEMIUS_API_BASE_URL", anything).and_return("https://api.freemius.test/v1")
  end

  describe ".configured?" do
    it "returns true when the API key is present" do
      expect(described_class.configured?).to be true
    end

    it "returns false when the API key is missing" do
      allow(ENV).to receive(:[]).with("FREEMIUS_API_KEY").and_return(nil)
      expect(described_class.configured?).to be false
    end
  end

  describe ".create_checkout" do
    it "posts to /checkouts and returns checkout_url and payment_id" do
      stub_request(:post, "https://api.freemius.test/v1/checkouts")
        .to_return(
          status: 200,
          body: { checkout_url: "https://checkout.freemius.test/c/abc", payment_id: "pay_123" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = described_class.create_checkout(
        amount_cents: 3000, currency: "USD", user_id: "u1", wallet_id: 2
      )

      expect(result["checkout_url"]).to eq("https://checkout.freemius.test/c/abc")
      expect(result["payment_id"]).to eq("pay_123")
    end

    it "raises ApiError when the API key is missing" do
      allow(ENV).to receive(:[]).with("FREEMIUS_API_KEY").and_return(nil)

      expect {
        described_class.create_checkout(amount_cents: 100, currency: "USD", user_id: "u1", wallet_id: 2)
      }.to raise_error(FreemiusClient::ApiError, /not configured/)
    end

    it "raises ApiError on non-200 responses" do
      stub_request(:post, "https://api.freemius.test/v1/checkouts")
        .to_return(status: 422, body: { error: "invalid amount" }.to_json)

      expect {
        described_class.create_checkout(amount_cents: -5, currency: "USD", user_id: "u1", wallet_id: 2)
      }.to raise_error(FreemiusClient::ApiError, /422/)
    end

    it "keeps wallet_topup metadata (separate from persona purchase)" do
      stub_request(:post, "https://api.freemius.test/v1/checkouts")
        .to_return(status: 200, body: { checkout_url: "https://x", payment_id: "p" }.to_json)

      described_class.create_checkout(amount_cents: 3000, currency: "USD", user_id: "u1", wallet_id: 2)

      expect(WebMock).to(have_requested(:post, "https://api.freemius.test/v1/checkouts")
        .with { |req| JSON.parse(req.body)["metadata"]["type"] == "wallet_topup" })
    end
  end

  describe ".create_persona_purchase_checkout" do
    it "posts to /checkouts with persona_purchase metadata and returns checkout_url" do
      stub_request(:post, "https://api.freemius.test/v1/checkouts")
        .to_return(
          status: 200,
          body: { checkout_url: "https://checkout.freemius.test/c/persona", payment_id: "pay_456" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = described_class.create_persona_purchase_checkout(
        amount_cents: 3000, currency: "JPY", user_id: "u1", listing_id: 42
      )

      expect(result["checkout_url"]).to eq("https://checkout.freemius.test/c/persona")
      expect(result["payment_id"]).to eq("pay_456")

      expect(WebMock).to(have_requested(:post, "https://api.freemius.test/v1/checkouts")
        .with { |req|
          body = JSON.parse(req.body)
          body["amount_cents"] == 3000 &&
            body["currency"] == "JPY" &&
            body["metadata"] == {
              "type" => "persona_purchase",
              "user_id" => "u1",
              "listing_id" => 42
            }
        })
    end

    it "raises ApiError when the API key is missing" do
      allow(ENV).to receive(:[]).with("FREEMIUS_API_KEY").and_return(nil)

      expect {
        described_class.create_persona_purchase_checkout(
          amount_cents: 3000, currency: "JPY", user_id: "u1", listing_id: 42
        )
      }.to raise_error(FreemiusClient::ApiError, /not configured/)
    end
  end

  describe ".get_payment / .get_subscription" do
    it "fetches a payment by ID" do
      stub_request(:get, "https://api.freemius.test/v1/payments/pay_123")
        .to_return(status: 200, body: { id: "pay_123", status: "completed" }.to_json)

      expect(described_class.get_payment("pay_123")["status"]).to eq("completed")
    end

    it "fetches a subscription by ID" do
      stub_request(:get, "https://api.freemius.test/v1/subscriptions/sub_1")
        .to_return(status: 200, body: { id: "sub_1", status: "active" }.to_json)

      expect(described_class.get_subscription("sub_1")["status"]).to eq("active")
    end
  end
end
