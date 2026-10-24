# frozen_string_literal: true

require 'spec_helper'

# 決済未設定・検索エンジン非zappy時の admin2 ガード（paypal / search_location）のカバレッジ
describe "Admin2 payment and search guards", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-guards.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "admin2guards",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "redirects paypal index when payments are not provisioned" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/payment-system/paypal"
    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(%r{/ja/admin\z|\Ahttp://#{@domain}/ja/admin\z})
  end

  it "redirects search settings when external search is not enabled" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/search-and-location/search"
    expect(response).to have_http_status(:redirect)
  end

  it "redirects location settings when external search is not enabled" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/search-and-location/location"
    expect(response).to have_http_status(:redirect)
  end
end
