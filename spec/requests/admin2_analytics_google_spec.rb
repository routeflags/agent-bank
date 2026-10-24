# frozen_string_literal: true

require 'spec_helper'

# admin2/analytics/google（Google Analytics 設定）のカバレッジ
describe "Admin2 Google Analytics settings", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-google.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "admin2google",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "renders google analytics index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/analytics/google-analytics"
    expect(response.status).to eq(200)
  end

  it "updates google analytics key with G- prefix" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/analytics/google-analytics/update_google",
          params: { community: { google_analytics_key: "G-TEST12345" } }
    expect(response.status).to eq(200)
    expect(@community.reload.google_analytics_key).to eq("G-TEST12345")
  end

  it "accepts legacy UA- prefixed key" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/analytics/google-analytics/update_google",
          params: { community: { google_analytics_key: "UA-12345678-1" } }
    expect(response.status).to eq(200)
    expect(@community.reload.google_analytics_key).to eq("UA-12345678-1")
  end

  it "rejects invalid analytics key" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/analytics/google-analytics/update_google",
          params: { community: { google_analytics_key: "INVALID-KEY" } }
    expect(response.status).to eq(422)
  end
end
