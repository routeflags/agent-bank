# frozen_string_literal: true

require 'spec_helper'

# 決済設定（payment_settings#index/create/redirect_to_stripe）のカバレッジ
describe "Payment settings flow", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "payment-settings.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @user = FactoryBot.create(:person, username: "paysettings", community_id: @community.id, member_of: @community)
  end

  def sign_in
    t = UserService::API::AuthTokens.create_login_token(@user.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "redirects to person settings when payments are not enabled" do
    bare_community = FactoryBot.create(:community, domain: "payment-bare.custom.org",
                                                   use_domain: true, settings: { "locales" => ["ja"] })
    bare_user = FactoryBot.create(:person, username: "paybare",
                                           community_id: bare_community.id, member_of: bare_community)
    t = UserService::API::AuthTokens.create_login_token(bare_user.id)[:token]
    get "http://payment-bare.custom.org/ja?auth=#{t}"
    get "http://payment-bare.custom.org/ja/#{bare_user.username}/settings/payments"
    expect(response).to have_http_status(:redirect)
  end

  it "renders payment settings index when payments are enabled" do
    FactoryBot.create(:payment_settings, community_id: @community.id, api_verified: true, payment_gateway: "stripe")
    sign_in
    get "http://#{@domain}/ja/#{@user.username}/settings/payments"
    expect(response.status).to eq(200)
  end

  it "redirects stripe callback without a stripe account" do
    FactoryBot.create(:payment_settings, community_id: @community.id, api_verified: true, payment_gateway: "stripe")
    sign_in
    get "http://#{@domain}/ja/#{@user.username}/settings/stripe_callback"
    expect(response).to have_http_status(:redirect)
  end

  it "redirects to stripe without a connected seller account" do
    FactoryBot.create(:payment_settings, community_id: @community.id, api_verified: true, payment_gateway: "stripe")
    sign_in
    get "http://#{@domain}/ja/#{@user.username}/settings/redirect_to_stripe"
    expect(response).to have_http_status(:redirect)
  end
end
