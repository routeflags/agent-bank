# frozen_string_literal: true

require 'rails_helper'

# Issue #59: Wallet#credit_seller_earning! / #seller_earning_credited?。
# deduct_for_usage! が手本。付与済み判定は seller_earning_credited? の1メソッドに集約。
RSpec.describe Wallet, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 0) }
  let(:usage_record) { UsageRecord.create!(input_tokens: 600, output_tokens: 400) }

  describe "#credit_seller_earning!" do
    it "残高を増やし seller_earning レコードを作成する" do
      record = wallet.credit_seller_earning!(900, usage_record: usage_record)

      expect(record).to be_present
      expect(record.transaction_type).to eq("seller_earning")
      expect(record.amount_cents).to eq(900)
      expect(record.reference_type).to eq("UsageRecord")
      expect(record.reference_id).to eq(usage_record.id)
      expect(wallet.reload.balance_cents).to eq(900)
    end

    it "二重付与は nil を返し残高は増えない" do
      wallet.credit_seller_earning!(900, usage_record: usage_record)

      expect(wallet.credit_seller_earning!(900, usage_record: usage_record)).to be_nil
      expect(wallet.reload.balance_cents).to eq(900)
      expect(wallet.credit_transactions.where(transaction_type: "seller_earning").count).to eq(1)
    end

    it "0以下の金額は付与しない" do
      expect(wallet.credit_seller_earning!(0, usage_record: usage_record)).to be_nil
      expect(wallet.reload.balance_cents).to eq(0)
      expect(wallet.credit_transactions.where(transaction_type: "seller_earning").count).to eq(0)
    end
  end

  describe "#seller_earning_credited?" do
    it "付与前は false、付与後は true" do
      expect(wallet.seller_earning_credited?(usage_record)).to be(false)

      wallet.credit_seller_earning!(1, usage_record: usage_record)

      expect(wallet.seller_earning_credited?(usage_record)).to be(true)
    end

    it "別の UsageRecord には影響されない" do
      wallet.credit_seller_earning!(1, usage_record: usage_record)
      other = UsageRecord.create!(input_tokens: 1, output_tokens: 0)

      expect(wallet.seller_earning_credited?(other)).to be(false)
    end
  end
end
