# frozen_string_literal: true

require 'spec_helper'

# 購入不要判定（Listing#free_to_use?）のスペック。
describe Listing, 'free_to_use?', type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }

  def build_listing(attrs = {})
    FactoryBot.create(:listing, { community_id: community.id, author: author }.merge(attrs))
  end

  it '価格 0 のペルソナは購入不要' do
    expect(build_listing(price: Money.new(0, "USD")).free_to_use?).to be true
  end

  it '価格が未設定のペルソナは購入不要' do
    expect(build_listing(price: nil, currency: "USD").free_to_use?).to be true
  end

  it '無料実行モード（default_run_mode == free）は購入不要' do
    listing = build_listing(price: Money.new(0, "USD"), default_run_mode: 'free')
    expect(listing.free_to_use?).to be true
  end

  it '価格が正の有料ペルソナは購入が必要' do
    expect(build_listing(price: Money.new(2000, "USD"), default_run_mode: 'run_online').free_to_use?).to be false
  end
end
