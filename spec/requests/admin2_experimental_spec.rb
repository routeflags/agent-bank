# frozen_string_literal: true

require 'spec_helper'

# admin2/advanced/new-features（実験的機能フラグ）のカバレッジ
describe "Admin2 experimental features", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-experimental.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "admin2exp",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "renders new features index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/advanced/new-features"
    expect(response.status).to eq(200)
  end

  it "updates experimental feature flags for community" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/advanced/new-features/update_experimental",
          params: { feature: { search: "enabled_for_community" } }
    expect(response.status).to eq(200)
  end
end
