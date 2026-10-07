# frozen_string_literal: true

require 'spec_helper'

# admin2/design/logos_color（ロゴ・favicon・カラーセット）のカバレッジ
describe "Admin2 logos and color", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-logos.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "admin2logos",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "renders logos and color index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/design/logos-and-color"
    expect(response.status).to eq(200)
  end

  it "updates custom color (JS response)" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/design/logos-and-color/update_logos_color",
          params: { community: { custom_color1: "#ffcc00" } }, xhr: true
    expect(response.status).to eq(200)
    expect(@community.reload.custom_color1).to eq("ffcc00")
  end

  it "handles remove_files for a missing attachment gracefully" do
    admin_sign_in
    expect {
      delete "http://#{@domain}/ja/admin/design/logos-and-color/remove_files",
             params: { type: "favicon" }, xhr: true
    }.not_to raise_error
    expect(response.status).to eq(200)
  end
end
