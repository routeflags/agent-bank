# frozen_string_literal: true

require 'spec_helper'

# Issue #106 Phase 2b: ランキングの評価表示と並び順。
#
# - 未評価（reviews_count=0）は「★ 0.0」ではなく「—」
# - 評価ありは「★ 4.3 (3)」
# - 並び順は total_sold → times_viewed → avg_rating（評価は同点時のタイブレーク）
RSpec.describe "ランキングの評価表示", type: :view do
  before(:all) do
    DatabaseCleaner.start
    @community = FactoryBot.create(:community, settings: { "locales" => ["ja"] })
    @owner = FactoryBot.create(:person, username: "rankingowner", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @owner, community: @community)
    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def render_index(listings)
    I18n.with_locale(:ja) do
      ApplicationController.render(
        template: "rankings/index",
        layout: false,
        assigns: { current_community: @community, ranked_listings: listings }
      )
    end
  end

  def build_listing(title, avg_rating: 0.0, reviews_count: 0, total_sold: 0, times_viewed: 0)
    listing = FactoryBot.create(:listing, community_id: @community.id, author: @owner, title: title)
    listing.update_columns(avg_rating: avg_rating, reviews_count: reviews_count,
                           total_sold: total_sold, times_viewed: times_viewed)
    listing.reload
  end

  it "評価がある出品は★と件数を出す" do
    listing = build_listing("評価ありランキング", avg_rating: 4.25, reviews_count: 3)

    html = render_index([listing])

    expect(html).to include("★ 4.3")
    expect(html).to include("(3)")
    expect(html).not_to include("raku-rank-item__rating-none")
  end

  it "未評価の出品は「—」を出し、★ 0.0 は出さない" do
    # Phase 2a の正規化前の状態（手動値 4.5 / レビュー 0 件）。
    listing = build_listing("未評価ランキング", avg_rating: 4.5, reviews_count: 0)

    html = render_index([listing])

    expect(html).to include("raku-rank-item__rating-none")
    expect(html).to include(I18n.t("lamprey.listings.rating_dash", locale: :ja))
    expect(html).not_to include("★")
    expect(html).not_to include("★ 0.0")
  end

  it "評価の有無が混在しても並び順は渡された順のまま描画する" do
    reviewed = build_listing("評価あり", avg_rating: 4.0, reviews_count: 1, total_sold: 5)
    unrated = build_listing("未評価", avg_rating: 4.5, reviews_count: 0, total_sold: 0)

    html = render_index([reviewed, unrated])
    doc = Nokogiri::HTML(html)

    expect(doc.css(".raku-rank-item__title").map(&:text)).to eq(["評価あり", "未評価"])
    expect(doc.css(".raku-rank-item__position").map(&:text)).to eq(["1", "2"])
  end
end
