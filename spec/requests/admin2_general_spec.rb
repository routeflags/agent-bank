# frozen_string_literal: true

require 'spec_helper'

# admin2/general 配下（privacy / essentials / admin-notifications）のカバレッジ
describe "Admin2 general settings", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-general.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @customization = @community.community_customizations.find_or_create_by(locale: "ja")
    @admin = FactoryBot.create(:person, username: "admin2general",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "renders privacy index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/general/privacy"
    expect(response.status).to eq(200)
  end

  it "updates community privacy setting" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/general/privacy/update_privacy",
          params: { community: { private: true } }
    expect(response.status).to eq(200)
    expect(@community.reload.private).to eq(true)
  end

  it "returns unprocessable when privacy params missing" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/general/privacy/update_privacy", params: {}
    expect(response.status).to eq(422)
  end

  it "renders essentials index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/general/essentials"
    expect(response.status).to eq(200)
  end

  it "updates essentials (customization + locales)" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/general/essentials/update_essential",
          params: {
            community: {
              show_slogan: true
            },
            community_customizations: {
              ja: { name: "更新後マーケット名" }
            },
            enabled_locales: %w[ja]
          }
    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(%r{/ja/admin/general/essentials\z})
    expect(@community.reload.show_slogan).to eq(true)
    expect(@customization.reload.name).to eq("更新後マーケット名")
  end

  it "renders admin notifications index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/general/admin-notifications"
    expect(response.status).to eq(200)
  end

  it "updates admin notifications flags" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/general/admin-notifications/update_admin_notifications",
          params: { community: { email_admins_about_new_members: true } }
    expect(response.status).to eq(200)
    expect(@community.reload.email_admins_about_new_members).to eq(true)
  end

  it "blocks non-admin users from admin area" do
    member = FactoryBot.create(:person, username: "admin2plain",
                                        community_id: @community.id, member_of: @community)
    t = UserService::API::AuthTokens.create_login_token(member.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
    get "http://#{@domain}/ja/admin/general/privacy"
    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(%r{\Ahttp://#{@domain}/})
  end
end
