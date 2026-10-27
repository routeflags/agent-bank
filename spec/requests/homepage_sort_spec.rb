# frozen_string_literal: true

require "spec_helper"

# Issue #80 / #81: トップと /browse の並び順タブ。
#
# 以前は JS が注目カード（スライダー）の DOM だけを並べ替えていたため、
# サーバーが描画する一覧グリッドの順序は変わらなかった。タブをリンクにし、
# DB 検索の ORDER BY を切り替える方式に変更した。
describe "一覧の並び順タブ", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "homepage-sort.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                                settings: { "locales" => ["en", "ja"] })
    @category = FactoryBot.create(:category, community: @community)
    @category.translation_attributes = { en: { name: "Sorting Category" } }
    @category.save!

    # sort_date（既定の並び）と created_at をずらし、avg_rating で差をつける。
    @oldest = create_listing("Sort Oldest", sort_date: 3.days.ago, created_at: 4.days.ago, avg_rating: 0)
    @rated = create_listing("Sort Rated", sort_date: 2.days.ago, created_at: 3.days.ago, avg_rating: 4.8)
    @newest = create_listing("Sort Newest", sort_date: 1.day.ago, created_at: 1.day.ago, avg_rating: 0)

    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def create_listing(title, sort_date:, created_at:, avg_rating:)
    listing = FactoryBot.create(:listing, community_id: @community.id,
                                           category: @category,
                                           title: title,
                                           avg_rating: avg_rating)
    listing.update_columns(sort_date: sort_date, created_at: created_at)
    listing
  end

  # 注目カード（スライダー）の並び = サーバーが返した一覧の並び。
  def featured_titles
    Nokogiri::HTML(response.body)
            .css(".raku-featured__card .raku-card__title")
            .map { |node| node.text.strip }
  end

  it "既定では sort_date の降順（サーバー既定の並び）" do
    get "http://#{@domain}/ja/browse"

    expect(response.status).to eq(200)
    expect(featured_titles).to eq(["Sort Newest", "Sort Rated", "Sort Oldest"])
  end

  it "?sort=newest は作成日時の降順" do
    get "http://#{@domain}/ja/browse?sort=newest"

    expect(response.status).to eq(200)
    expect(featured_titles).to eq(["Sort Newest", "Sort Rated", "Sort Oldest"])
  end

  it "?sort=rating は評価の降順" do
    get "http://#{@domain}/ja/browse?sort=rating"

    expect(response.status).to eq(200)
    expect(featured_titles).to eq(["Sort Rated", "Sort Newest", "Sort Oldest"])
  end

  it "未知の sort 値は既定の並びに戻す" do
    get "http://#{@domain}/ja/browse?sort=unknown"

    expect(response.status).to eq(200)
    expect(featured_titles).to eq(["Sort Newest", "Sort Rated", "Sort Oldest"])
  end

  it "タブはサーバー側の並べ替え用リンクで、現在の並び順が is-active になる" do
    get "http://#{@domain}/ja/browse?sort=rating"

    doc = Nokogiri::HTML(response.body)
    tabs = doc.css(".raku-featured__tab")
    expect(tabs.map { |tab| tab["data-sort"] }).to eq(%w[popular newest rating])

    active = tabs.select { |tab| tab["class"].to_s.include?("is-active") }
    expect(active.map { |tab| tab["data-sort"] }).to eq(["rating"])

    # リンクは現在のパスと他のクエリを保持する
    expect(tabs.map { |tab| tab["href"] }).to include("/ja/browse?sort=newest")
  end
end
