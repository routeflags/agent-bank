# frozen_string_literal: true

require 'spec_helper'

# admin2/users 配下（signup-and-login / user-fields）のカバレッジ
describe "Admin2 users settings", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-users.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @customization = @community.community_customizations.find_or_create_by(locale: "ja")
    @admin = FactoryBot.create(:person, username: "admin2users",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "renders signup and login index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/users/signup-and-login"
    expect(response.status).to eq(200)
  end

  it "updates signup/login settings" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/users/signup-and-login/update_signup_login",
          params: {
            community: {
              join_with_invite_only: true,
              community_customizations_attributes: [
                { id: @customization.id, signup_info_content: "招待制です" }
              ]
            }
          }
    expect(response.status).to eq(200)
    expect(@community.reload.join_with_invite_only).to eq(true)
  end

  it "renders user fields index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/users/user-fields"
    expect(response.status).to eq(200)
  end
end
