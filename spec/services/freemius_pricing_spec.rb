# frozen_string_literal: true

require 'rails_helper'

# JPY → USD conversion for Freemius billing (Issue #43 follow-up).
# The rate comes from FREEMIUS_JPY_USD_RATE (USD per 1 JPY, e.g. 0.0067).
# There is no default rate: missing/invalid means unconfigured.
RSpec.describe FreemiusPricing do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return("0.0067")
    allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_PRICE_MAP").and_call_original
    allow(ENV).to receive(:[]).with("FREEMIUS_PRICE_TOLERANCE_PCT").and_call_original
  end

  describe ".rate" do
    it "parses a valid rate" do
      expect(described_class.rate).to eq(0.0067)
    end

    it "strips surrounding whitespace" do
      allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return(" 0.0067 \n")
      expect(described_class.rate).to eq(0.0067)
    end

    it "returns nil when missing or blank" do
      allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return(nil)
      expect(described_class.rate).to be_nil
      expect(described_class.configured?).to be false
    end

    it "returns nil for non-numeric, zero, negative, NaN, and Infinity" do
      %w[abc 0 0.0 -1 -0.0067 NaN Infinity -Infinity].each do |bad|
        allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return(bad)
        expect(described_class.rate).to be_nil, "expected nil for #{bad.inspect}"
      end
      expect(described_class.configured?).to be false
    end
  end

  describe ".usd_cents_for_jpy" do
    it "converts 3000 yen at 0.0067 to 2010 cents" do
      expect(described_class.usd_cents_for_jpy(3000)).to eq(2010)
    end

    it "maps 0 yen to 0 (no ceil artifact)" do
      expect(described_class.usd_cents_for_jpy(0)).to eq(0)
    end

    it "rounds UP fractional cents (1 yen * 0.0067 = 0.67 -> 1)" do
      expect(described_class.usd_cents_for_jpy(1)).to eq(1)
    end

    it "rounds UP non-trivial fractions (100 yen * 0.00673 = 67.3 -> 68)" do
      allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return("0.00673")
      expect(described_class.usd_cents_for_jpy(100)).to eq(68)
    end

    it "handles very large amounts exactly (9,999,999 yen -> 6,700,000 cents)" do
      expect(described_class.usd_cents_for_jpy(9_999_999)).to eq(6_700_000)
    end

    it "avoids binary float error (BigDecimal, not Float math)" do
      # 29 yen * 0.0067 = 19.43 exactly; Float(0.0067) * 29 * 100
      # can land on 19.42999... and floor to 19. ceil(BigDecimal) is stable.
      expect(described_class.usd_cents_for_jpy(29)).to eq(20)
    end

    it "maps negative input to 0 instead of raising" do
      expect(described_class.usd_cents_for_jpy(-5)).to eq(0)
    end

    it "raises RateMissingError when the rate is unconfigured" do
      allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return(nil)
      expect {
        described_class.usd_cents_for_jpy(3000)
      }.to raise_error(described_class::RateMissingError, /FREEMIUS_JPY_USD_RATE/)
    end
  end

  describe ".amounts_for_jpy" do
    it "returns the full breakdown for API responses" do
      expect(described_class.amounts_for_jpy(3000)).to eq({
        amount_jpy: 3000,
        amount_usd_cents: 2010,
        currency: "usd",
        fx_rate: 0.0067
      })
    end
  end

  describe ".format_usd" do
    it "formats cents as dollars" do
      expect(described_class.format_usd(2010)).to eq("20.10")
      expect(described_class.format_usd(67)).to eq("0.67")
    end
  end

  describe ".check_plan_price" do
    it "returns :unknown when no plan price map is configured" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_PRICE_MAP").and_return(nil)
      expect(described_class.check_plan_price("5678", 2010)).to eq(:unknown)
    end

    it "returns :ok when within tolerance" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_PRICE_MAP")
        .and_return({ "5678" => 1999 }.to_json)
      expect(described_class.check_plan_price("5678", 2010)).to eq(:ok)
    end

    it "returns :mismatch and warns when drift exceeds tolerance" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_PRICE_MAP")
        .and_return({ "5678" => 999 }.to_json)
      allow(Rails.logger).to receive(:warn)
      expect(described_class.check_plan_price("5678", 2010)).to eq(:mismatch)
      expect(Rails.logger).to have_received(:warn).with(/plan price drift/)
    end

    it "treats broken JSON map as :unknown" do
      allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_PRICE_MAP").and_return("{oops")
      expect(described_class.check_plan_price("5678", 2010)).to eq(:unknown)
    end
  end
end
