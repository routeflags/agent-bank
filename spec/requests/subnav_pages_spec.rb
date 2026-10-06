# frozen_string_literal: true

require 'spec_helper'

# サブナビ新設ページ（ランキング / バトル / ドキュメント）の描画ガード
describe "Sub-navigation pages", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "subnav-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @seller = FactoryBot.create(:person, username: "rankauthor", community_id: @community.id)
    @ranking_listing = FactoryBot.create(:listing,
                                          community_id: @community.id,
                                          author: @seller,
                                          title: "Ranked persona",
                                          avg_rating: 4.8,
                                          total_sold: 12)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "renders the rankings page with open listings" do
    get "http://#{@domain}/ja/rankings"

    expect(response.status).to eq(200)
    expect(response.body).to include("ペルソナランキング")
    expect(response.body).to include("Ranked persona")
    expect(response.body).to include("raku-rank-item")
  end

  it "renders the battles page in its coming-soon state" do
    get "http://#{@domain}/ja/battles"

    expect(response.status).to eq(200)
    expect(response.body).to include("ペルソナバトル")
    expect(response.body).to include("準備中")
  end

  it "renders the docs page" do
    get "http://#{@domain}/ja/docs"

    expect(response.status).to eq(200)
    expect(response.body).to include("ドキュメント")
    expect(response.body).to include("raku-docs-section")
  end

  it "marks the current sub-nav item as active on each page" do
    get "http://#{@domain}/ja/rankings"
    expect(response.body).to match(/raku-nav__link is-active[^>]*href="[^"]*rankings"/)

    get "http://#{@domain}/ja/docs"
    expect(response.body).to match(/raku-nav__link is-active[^>]*href="[^"]*docs"/)
  end
end
