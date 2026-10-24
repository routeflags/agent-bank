# frozen_string_literal: true

require 'rails_helper'

# Fixed-amount prepaid plans (Issue #46).
# FREEMIUS_TOPUP_PLAN_MAP is the sole source of truth for plan_id -> credit (yen).
RSpec.describe FreemiusTopupPlans do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_call_original
    allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return("0.0067")
  end

  def stub_topup_map(raw)
    allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_return(raw)
  end

  describe ".configured? / .validation_errors" do
    it "is not configured when the map is missing" do
      stub_topup_map(nil)
      expect(described_class.configured?).to be false
      expect(described_class.validation_errors.join).to match(/not configured/)
    end

    it "is not configured for broken JSON" do
      stub_topup_map("{oops")
      expect(described_class.configured?).to be false
      expect(described_class.plans).to eq({})
    end

    it "is not configured for an empty object" do
      stub_topup_map("{}")
      expect(described_class.configured?).to be false
    end

    it "rejects non-positive and out-of-range credits" do
      stub_topup_map({ "1" => 0, "2" => -5, "3" => 50 }.to_json)
      expect(described_class.configured?).to be false
      expect(described_class.validation_errors.size).to eq(3)
    end

    it "detects duplicate raw keys" do
      stub_topup_map('{"5678":1000,"5678":3000}')
      expect(described_class.validation_errors.any? { |e| e.include?("duplicate") }).to be true
      expect(described_class.configured?).to be false
    end

    it "is configured for a valid map" do
      stub_topup_map({ "5678" => 1000, "5679" => 3000 }.to_json)
      expect(described_class.configured?).to be true
      expect(described_class.plans).to eq({ "5678" => 1000, "5679" => 3000 })
    end
  end

  describe ".credit_for_plan" do
    before { stub_topup_map({ "5678" => 1000, "5679" => 3000 }.to_json) }

    it "resolves exact plan_id only (no prefix confusion)" do
      expect(described_class.credit_for_plan("5678")).to eq(1000)
      expect(described_class.credit_for_plan(5679)).to eq(3000)
      expect(described_class.credit_for_plan("567")).to be_nil
      expect(described_class.credit_for_plan("56780")).to be_nil
      expect(described_class.credit_for_plan(nil)).to be_nil
      expect(described_class.credit_for_plan(" ")).to be_nil
    end
  end

  describe ".available_denominations" do
    it "returns sorted denominations with USD estimates via FreemiusPricing" do
      stub_topup_map({ "5679" => 3000, "5678" => 1000 }.to_json)
      denoms = described_class.available_denominations
      expect(denoms.map { |d| d[:plan_id] }).to eq(%w[5678 5679])
      first = denoms.first
      expect(first[:credit_jpy]).to eq(1000)
      expect(first[:estimated_usd_cents]).to eq(670)
      expect(first[:currency]).to eq("usd")
      expect(first[:fx_rate]).to eq(0.0067)
    end

    it "returns [] when the FX rate is unconfigured (fail-closed)" do
      stub_topup_map({ "5678" => 1000 }.to_json)
      allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return(nil)
      expect(described_class.available_denominations).to eq([])
    end

    it "returns [] when the map is invalid" do
      stub_topup_map(nil)
      expect(described_class.available_denominations).to eq([])
    end
  end
end
