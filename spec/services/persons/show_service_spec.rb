# frozen_string_literal: true

require 'spec_helper'

# 回帰防止: プロフィールの「出品中スキル」はプロフィール本人の出品のみを
# 表示すること（他人の出品が混入しない）。2026-10-06 デザインレビューの
# フォローアップで追加。
describe Persons::ShowService do
  let(:community) { FactoryBot.create(:community) }
  let(:seller) do
    FactoryBot.create(:person, community_id: community.id, username: "seller_#{SecureRandom.hex(3)}")
  end
  let(:buyer) do
    FactoryBot.create(:person, community_id: community.id, username: "buyer_#{SecureRandom.hex(3)}")
  end
  let(:stranger) do
    FactoryBot.create(:person, community_id: community.id, username: "stranger_#{SecureRandom.hex(3)}")
  end

  def create_listing(author, title:, open: true)
    FactoryBot.create(:listing, community_id: community.id, author: author, title: title, open: open)
  end

  def listings_for(person, params = {})
    service = described_class.new(
      community: community,
      params: { username: person.username }.merge(params),
      current_user: person
    )
    service.listings
  end

  describe "#listings" do
    it "returns only the profile person's listings" do
      mine = create_listing(seller, title: "Seller persona")
      create_listing(stranger, title: "Someone else's persona")

      results = listings_for(seller)

      expect(results.map { |l| l[:title] }).to eq(["Seller persona"])
      expect(results.map { |l| l[:id] }).to eq([mine.id])
    end

    it "returns an empty list for a person without listings" do
      create_listing(seller, title: "Seller persona")

      expect(listings_for(buyer)).to eq([])
    end

    it "excludes closed listings for viewers other than the owner" do
      create_listing(seller, title: "Closed persona", open: false)

      expect(listings_for(buyer)).to eq([])
    end

    it "includes closed listings for the owner when show_closed is set" do
      create_listing(seller, title: "Closed persona", open: false)
      create_listing(seller, title: "Open persona", open: true)

      results = listings_for(seller, show_closed: "true")

      expect(results.map { |l| l[:title] }).to match_array(["Closed persona", "Open persona"])
    end

    it "does not include closed listings for the owner without show_closed" do
      create_listing(seller, title: "Closed persona", open: false)
      create_listing(seller, title: "Open persona", open: true)

      results = listings_for(seller)

      expect(results.map { |l| l[:title] }).to eq(["Open persona"])
    end
  end
end
