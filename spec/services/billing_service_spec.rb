# frozen_string_literal: true

require 'rails_helper'

# Issue #59（新仕様）: トークン単価課金＋出品者収益分配。
#
# - base = ceil(price_cents × total_tokens / 1_000_000)、最低 1、上乗せなし（total = base）
# - fee = floor(base × platform_commission_rate / 100)
# - payout = base - fee を店子のウォレットへ seller_earning として付与（請求と同一Tx）
RSpec.describe BillingService, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:seller) { FactoryBot.create(:person, community_id: community.id) }
  let(:buyer) { FactoryBot.create(:person, community_id: community.id) }

  before do
    FactoryBot.create(:community_membership, person: seller, community: community)
    FactoryBot.create(:community_membership, person: buyer, community: community)
    FactoryBot.create(:payment_settings, community_id: community.id, platform_commission_rate: 10)
  end

  def build_listing(price_cents:)
    FactoryBot.create(
      :listing,
      community_id: community.id,
      author: seller,
      price: Money.new(price_cents, "JPY")
    )
  end

  def build_usage(input_tokens: 600, output_tokens: 400)
    UsageRecord.create!(input_tokens: input_tokens, output_tokens: output_tokens)
  end

  def build_service(buyer_balance_cents:, price_cents:, usage: nil)
    listing = build_listing(price_cents: price_cents)
    FactoryBot.create(:wallet, person: buyer, community: community, balance_cents: buyer_balance_cents)
    usage_record = usage || build_usage
    service = BillingService.new(person: buyer, usage_record: usage_record, listing: listing)
    [service, listing, usage_record]
  end

  describe "受入例1: 単価1,000円/100万トークン × 1,000トークン、手数料率10%" do
    it "base=1・fee=0・payout=1・total=1 になる" do
      service, _listing, _usage = build_service(buyer_balance_cents: 100, price_cents: 1_000)

      charges = service.process!

      expect(charges[:base_cost_cents]).to eq(1)
      expect(charges[:platform_commission_pct]).to eq(10)
      expect(charges[:platform_commission_cents]).to eq(0)
      expect(charges[:seller_payout_cents]).to eq(1)
      expect(charges[:total_charge_cents]).to eq(1)
      expect(charges).not_to have_key(:seller_commission_cents)
      expect(charges).not_to have_key(:seller_commission_pct)
    end

    it "購入者は1減り、店子は1増える" do
      service, listing, usage_record = build_service(buyer_balance_cents: 100, price_cents: 1_000)
      seller_wallet = seller.find_or_create_wallet!(community: community)

      service.process!

      expect(buyer.wallet.reload.balance_cents).to eq(99)
      expect(seller_wallet.reload.balance_cents).to eq(1)
      earning = seller_wallet.credit_transactions.find_by(
        transaction_type: "seller_earning",
        reference_type: "UsageRecord",
        reference_id: usage_record.id
      )
      expect(earning).to be_present
      expect(earning.amount_cents).to eq(1)
      meta = JSON.parse(earning.metadata)
      expect(meta["listing_id"]).to eq(listing.id)
      expect(meta["seller_payout_cents"]).to eq(1)
    end
  end

  describe "受入例2: 単価1,000,000円/100万トークン × 1,000トークン、手数料率10%" do
    it "base=1,000・fee=100・payout=900・total=1,000 になる" do
      service, _listing, _usage = build_service(buyer_balance_cents: 2_000, price_cents: 1_000_000)

      charges = service.process!

      expect(charges[:base_cost_cents]).to eq(1_000)
      expect(charges[:platform_commission_cents]).to eq(100)
      expect(charges[:seller_payout_cents]).to eq(900)
      expect(charges[:total_charge_cents]).to eq(1_000)
    end

    it "購入者は上乗せなしで1,000減り、店子は900増える" do
      service, _listing, _usage = build_service(buyer_balance_cents: 2_000, price_cents: 1_000_000)
      seller_wallet = seller.find_or_create_wallet!(community: community)

      service.process!

      expect(buyer.wallet.reload.balance_cents).to eq(1_000)
      expect(seller_wallet.reload.balance_cents).to eq(900)
    end
  end

  describe "切り上げ" do
    it "端数は切り上げ・最低1（単価150万円 × 1トークン = 2）" do
      service, _listing, _usage = build_service(
        buyer_balance_cents: 100, price_cents: 1_500_000, usage: build_usage(input_tokens: 1, output_tokens: 0)
      )

      charges = service.calculate_charges

      expect(charges[:base_cost_cents]).to eq(2)
    end
  end

  describe "platform_commission_rate が nil のとき" do
    it "commission_from_seller にフォールバックする" do
      PaymentSettings.where(community_id: community.id).update_all(platform_commission_rate: nil, commission_from_seller: 20)
      service, _listing, _usage = build_service(buyer_balance_cents: 2_000, price_cents: 1_000_000)

      charges = service.calculate_charges

      expect(charges[:platform_commission_pct]).to eq(20)
      expect(charges[:platform_commission_cents]).to eq(200)
      expect(charges[:seller_payout_cents]).to eq(800)
    end
  end

  describe "冪等性" do
    it "同じ UsageRecord で二重処理しても付与は1回" do
      service, _listing, usage_record = build_service(buyer_balance_cents: 5_000, price_cents: 1_000_000)
      seller_wallet = seller.find_or_create_wallet!(community: community)

      service.process!
      BillingService.new(person: buyer, usage_record: usage_record,
                         listing: service.listing).process!

      expect(seller_wallet.credit_transactions.where(
        transaction_type: "seller_earning",
        reference_type: "UsageRecord",
        reference_id: usage_record.id
      ).count).to eq(1)
      expect(seller_wallet.reload.balance_cents).to eq(900)
    end

    it "DB制約が重複レコードを拒否する" do
      _service, listing, usage_record = build_service(buyer_balance_cents: 5_000, price_cents: 1_000_000)
      seller_wallet = seller.find_or_create_wallet!(community: community)
      seller_wallet.credit_seller_earning!(900, usage_record: usage_record, listing: listing)

      expect do
        seller_wallet.credit_transactions.create!(
          transaction_type: "seller_earning",
          amount_cents: 900,
          reference_type: "UsageRecord",
          reference_id: usage_record.id
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "残高不足" do
    it "請求が失敗したら店子への付与も発生しない" do
      service, _listing, usage_record = build_service(buyer_balance_cents: 0, price_cents: 1_000_000)
      seller_wallet = seller.find_or_create_wallet!(community: community)

      expect { service.process! }.to raise_error(Wallet::InsufficientBalanceError)

      expect(seller_wallet.reload.balance_cents).to eq(0)
      expect(seller_wallet.credit_transactions.where(transaction_type: "seller_earning").count).to eq(0)
      expect(usage_record.reload.charge_cents).to eq(0)
    end
  end

  describe "単価未設定・0 の出品" do
    it "base=0・請求0・付与なし" do
      listing = build_listing(price_cents: 1_000)
      listing.update_column(:price_cents, nil)
      FactoryBot.create(:wallet, person: buyer, community: community, balance_cents: 100)
      usage_record = build_usage
      seller_wallet = seller.find_or_create_wallet!(community: community)
      service = BillingService.new(person: buyer, usage_record: usage_record, listing: listing)

      charges = service.process!

      expect(charges[:base_cost_cents]).to eq(0)
      expect(charges[:total_charge_cents]).to eq(0)
      expect(charges[:seller_payout_cents]).to eq(0)
      expect(buyer.wallet.reload.balance_cents).to eq(100)
      expect(seller_wallet.reload.balance_cents).to eq(0)
      expect(seller_wallet.credit_transactions.where(transaction_type: "seller_earning").count).to eq(0)
    end
  end
end
