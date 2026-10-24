# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FreemiusClient do
  let(:bearer) { "test_bearer_token" }
  let(:product_id) { "1234" }

  before do
    stub_const("FreemiusClient::DEFAULT_BASE_URL", "https://api.freemius.test/v1")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("API_BEARER_AUTHORIZATION_TOKEN").and_return(bearer)
    allow(ENV).to receive(:[]).with("FREEMIUS_API_KEY").and_return(nil)
    allow(ENV).to receive(:[]).with("FREEMIUS_PRODUCT_ID").and_return(product_id)
    allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_ID").and_call_original
    allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_MAP").and_call_original
    allow(ENV).to receive(:[]).with("PRODUCT_SECRET_KEY").and_call_original
    allow(ENV).to receive(:[]).with("FREEMIUS_WEBHOOK_SECRET").and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("FREEMIUS_API_BASE_URL", anything).and_return("https://api.freemius.test/v1")
  end

  describe ".product_id" do
    it "prefers PRODUCT_ID（`.env` の新しい命名）over the legacy key" do
      allow(ENV).to receive(:[]).with("PRODUCT_ID").and_return("5678")

      expect(described_class.product_id).to eq("5678")
    end

    it "falls back to FREEMIUS_PRODUCT_ID when PRODUCT_ID is absent" do
      allow(ENV).to receive(:[]).with("PRODUCT_ID").and_return(nil)

      expect(described_class.product_id).to eq("1234")
    end

    it "is nil when neither key is configured" do
      allow(ENV).to receive(:[]).with("PRODUCT_ID").and_return(nil)
      allow(ENV).to receive(:[]).with("FREEMIUS_PRODUCT_ID").and_return(nil)

      expect(described_class.product_id).to be_nil
    end
  end

  describe ".configured?" do
    it "returns true when product_id and Bearer are present" do
      expect(described_class.configured?).to be true
    end

    it "returns false when the Bearer token is missing" do
      allow(ENV).to receive(:[]).with("API_BEARER_AUTHORIZATION_TOKEN").and_return(nil)
      expect(described_class.configured?).to be false
    end

    it "returns false when the product_id is missing" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PRODUCT_ID").and_return(nil)
      expect(described_class.configured?).to be false
    end

    it "falls back to FREEMIUS_API_KEY for backward compatibility" do
      allow(ENV).to receive(:[]).with("API_BEARER_AUTHORIZATION_TOKEN").and_return(nil)
      allow(ENV).to receive(:[]).with("FREEMIUS_API_KEY").and_return(bearer)
      expect(described_class.configured?).to be true
    end
  end

  describe ".build_hosted_checkout_url" do
    it "builds a plan-based hosted URL with user_email" do
      url = described_class.build_hosted_checkout_url(plan_id: "5678", user_email: "a@example.com")

      expect(url).to start_with("https://checkout.freemius.com/product/1234/plan/5678/")
      expect(url).to include("user_email=a%40example.com")
      expect(url).to include("readonly_user=true")
    end

    it "raises ApiError when plan_id is blank" do
      expect {
        described_class.build_hosted_checkout_url(plan_id: " ")
      }.to raise_error(FreemiusClient::ApiError, /plan_id/)
    end

    it "raises ApiError when product_id is missing" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PRODUCT_ID").and_return(nil)

      expect {
        described_class.build_hosted_checkout_url(plan_id: "5678")
      }.to raise_error(FreemiusClient::ApiError, /FREEMIUS_PRODUCT_ID/)
    end
  end

  describe ".plan_id_for_listing / .listing_id_for_plan" do
    it "resolves a single plan from FREEMIUS_PLAN_ID" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_MAP").and_return(nil)
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_ID").and_return("5678")
      listing = double(id: 42)

      expect(described_class.plan_id_for_listing(listing)).to eq("5678")
    end

    it "prefers FREEMIUS_PLAN_MAP over the single plan" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_MAP").and_return({ "42" => "9999" }.to_json)
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_ID").and_return("5678")
      listing = double(id: 42)

      expect(described_class.plan_id_for_listing(listing)).to eq("9999")
      expect(described_class.listing_id_for_plan("9999")).to eq(42)
    end

    it "returns nil when no plan is resolvable" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_MAP").and_return(nil)
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_ID").and_return(nil)
      listing = double(id: 42)

      expect(described_class.plan_id_for_listing(listing)).to be_nil
    end
  end

  describe ".payment_amount_cents" do
    it "converts gross float to cents" do
      expect(described_class.payment_amount_cents({ "gross" => 30.0 })).to eq(3000)
    end

    it "accepts legacy amount_cents" do
      expect(described_class.payment_amount_cents({ "amount_cents" => 3000 })).to eq(3000)
    end
  end

  describe ".get_payment / .get_subscription (product scope)" do
    it "fetches a payment by ID with Bearer auth" do
      stub = stub_request(:get, "https://api.freemius.test/v1/products/1234/payments/pay_123.json")
        .to_return(status: 200, body: { id: "pay_123", gross: 30.0, currency: "usd" }.to_json)

      result = described_class.get_payment("pay_123")

      expect(result["gross"]).to eq(30.0)
      expect(stub).to have_been_requested
      expect(WebMock).to(have_requested(:get, "https://api.freemius.test/v1/products/1234/payments/pay_123.json")
        .with(headers: { "Authorization" => "Bearer #{bearer}" }))
    end

    it "fetches a subscription by ID with Bearer auth" do
      stub_request(:get, "https://api.freemius.test/v1/products/1234/subscriptions/sub_1.json")
        .to_return(status: 200, body: { id: "sub_1", status: "active" }.to_json)

      expect(described_class.get_subscription("sub_1")["status"]).to eq("active")
    end

    it "raises ApiError when credentials are missing" do
      allow(ENV).to receive(:[]).with("API_BEARER_AUTHORIZATION_TOKEN").and_return(nil)

      expect {
        described_class.get_payment("pay_123")
      }.to raise_error(FreemiusClient::ApiError, /not configured/)
    end

    it "raises ApiError on non-200 responses" do
      stub_request(:get, "https://api.freemius.test/v1/products/1234/payments/missing.json")
        .to_return(status: 404, body: { error: "not found" }.to_json)

      expect {
        described_class.get_payment("missing")
      }.to raise_error(FreemiusClient::ApiError, /404/)
    end
  end
end
