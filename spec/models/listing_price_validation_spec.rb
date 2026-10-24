# frozen_string_literal: true

require 'spec_helper'

# Issue #52: 全出品は有料。価格は「円 / 100万トークン」の単価として必須。
# nil/0 では保存できない。
describe Listing, 'price validation', type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }

  def build_listing(attrs = {})
    FactoryBot.build(:listing, { community_id: community.id, author: author }.merge(attrs))
  end

  it '価格が正の整数なら有効' do
    expect(build_listing(price: Money.new(2000, "USD"))).to be_valid
  end

  it '価格が未設定（nil）なら無効' do
    listing = build_listing(price: nil, currency: "USD")
    expect(listing).not_to be_valid
    expect(listing.errors[:price_cents].join).to include("100万トークン")
  end

  it '価格が 0 なら無効' do
    listing = build_listing(price: Money.new(0, "USD"))
    expect(listing).not_to be_valid
    expect(listing.errors[:price_cents].join).to include("100万トークン")
  end

  it '価格が負なら無効' do
    listing = build_listing(price_cents: -100)
    expect(listing).not_to be_valid
  end
end
