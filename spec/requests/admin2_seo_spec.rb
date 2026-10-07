# frozen_string_literal: true

require 'spec_helper'

# admin2/seo 配下（メタタグ5系統 + sitemap / google-console）のカバレッジ
describe "Admin2 SEO settings", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-seo.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @customization = @community.community_customizations.find_or_create_by(locale: "ja")
    @admin = FactoryBot.create(:person, username: "admin2seo",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "renders sitemap-and-robots index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/seo/sitemap-and-robots"
    expect(response.status).to eq(200)
  end

  it "renders google-search-console index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/seo/google-search-console"
    expect(response.status).to eq(200)
  end

  it "renders and updates listing pages meta tags" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/seo/listing-pages-meta-tags"
    expect(response.status).to eq(200)

    patch "http://#{@domain}/ja/admin/seo/listing-pages-meta-tags/update_listing_page",
          params: { community: { community_customizations_attributes: [
            { id: @customization.id, listing_meta_title: "出品ページ用タイトル" }
          ] } }
    expect(response.status).to eq(200)
    expect(@customization.reload.listing_meta_title).to eq("出品ページ用タイトル")
  end

  it "renders and updates search pages meta tags" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/seo/search-page-meta-tags"
    expect(response.status).to eq(200)

    patch "http://#{@domain}/ja/admin/seo/search-page-meta-tags/update_search_pages",
          params: { community: { community_customizations_attributes: [
            { id: @customization.id, search_meta_title: "検索ページ用タイトル" }
          ] } }
    expect(response.status).to eq(200)
    expect(@customization.reload.search_meta_title).to eq("検索ページ用タイトル")
  end

  it "renders and updates landing page meta tags" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/seo/landing-page-meta-tags"
    expect(response.status).to eq(200)

    patch "http://#{@domain}/ja/admin/seo/landing-page-meta-tags/update_landing_page",
          params: { community: { community_customizations_attributes: [
            { id: @customization.id, meta_title: "LP用タイトル" }
          ] } }
    expect(response.status).to eq(200)
    expect(@customization.reload.meta_title).to eq("LP用タイトル")
  end

  it "renders and updates category pages meta tags" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/seo/category-pages-meta-tags"
    expect(response.status).to eq(200)

    patch "http://#{@domain}/ja/admin/seo/category-pages-meta-tags/update_category_page",
          params: { community: { community_customizations_attributes: [
            { id: @customization.id, category_meta_title: "カテゴリ用タイトル" }
          ] } }
    expect(response.status).to eq(200)
    expect(@customization.reload.category_meta_title).to eq("カテゴリ用タイトル")
  end

  it "renders and updates profile pages meta tags" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/seo/profile-pages-meta-tags"
    expect(response.status).to eq(200)

    patch "http://#{@domain}/ja/admin/seo/profile-pages-meta-tags/update_profile_page",
          params: { community: { community_customizations_attributes: [
            { id: @customization.id, profile_meta_title: "プロフィール用タイトル" }
          ] } }
    expect(response.status).to eq(200)
    expect(@customization.reload.profile_meta_title).to eq("プロフィール用タイトル")
  end
end
