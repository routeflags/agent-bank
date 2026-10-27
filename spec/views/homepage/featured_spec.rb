# frozen_string_literal: true

require "spec_helper"

# トップの「注目のスキル」カード。
#
# Issue #52 で価格表示の条件に `listing.price_cents` を入れたが、検索結果は
# `ListingIndexViewUtils::ListingItem` という Struct で `price_cents` を持たない。
# 価格付きの出品があるとトップページが 500 になったため、実際に描画して担保する。
RSpec.describe "トップの注目カード", type: :view do
  def build_item(price)
    ListingIndexViewUtils::ListingItem.new(
      1,                        # id
      "/listings/1",           # url
      "テスト出品",              # title
      nil,                      # category_id
      nil,                      # latitude
      nil,                      # longitude
      nil,                      # distance
      nil,                      # distance_unit
      nil,                      # author
      "説明文",                  # description
      [],                       # listing_images
      price                     # price (Money)
    )
  end

  def render_featured(listings)
    ApplicationController.render(
      partial: "homepage/featured",
      assigns: { listings: listings, featured_ratings: {} }
    )
  end

  it "価格付きの出品を描画できる（ListingItem に price_cents は無い）" do
    html = render_featured([build_item(Money.new(1000, "JPY"))])

    expect(html).to include("テスト出品")
    expect(html).to include("¥1,000")
  end

  it "価格が 0 の出品では金額を表示しない" do
    html = render_featured([build_item(Money.new(0, "JPY"))])

    expect(html).to include("テスト出品")
    expect(html).not_to include("¥0")
  end

  # Issue #108: 評価（★・レビュー件数・高評価タブ）は #106 保留のため
  # トップに出さない。タブはおすすめ・新着の 2 つのみ。
  it "評価も高評価タブも表示しない" do
    html = render_featured([build_item(Money.new(1000, "JPY"))])

    expect(html).not_to include("★")
    expect(html).not_to include("rating")
    expect(Nokogiri::HTML(html).css(".raku-featured__tab").map { |tab| tab["data-sort"] }).to eq(%w[popular newest])
  end
end
