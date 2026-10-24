# frozen_string_literal: true

require 'spec_helper'

# 小規模 admin2 コントローラ群（twitter / static-content / google-tag-manager /
# conversations / plans / user-fields）のカバレッジ
describe "Admin2 misc controllers", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-misc.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "admin2misc",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)

    @seller = FactoryBot.create(:person, username: "miscseller", community_id: @community.id, member_of: @community)
    @buyer = FactoryBot.create(:person, username: "miscbuyer", community_id: @community.id, member_of: @community)
    @conversation = FactoryBot.create(:conversation, community: @community)
    FactoryBot.create(:participation, conversation: @conversation, person: @seller, is_starter: true)
    FactoryBot.create(:participation, conversation: @conversation, person: @buyer, is_starter: false)
    FactoryBot.create(:message, conversation: @conversation, sender: @buyer, content: "misc用メッセージ")
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  it "renders and updates twitter settings" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/social-media/twitter"
    expect(response.status).to eq(200)

    patch "http://#{@domain}/ja/admin/social-media/twitter/update_twitter",
          params: { community: { twitter_handle: "@routeflags" } }
    expect(response.status).to eq(200)
    # twitter_handle は @ を除去して保存される
    expect(@community.reload.twitter_handle).to eq("routeflags")
  end

  it "renders static content index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/general/static-content"
    expect(response.status).to eq(200)
  end

  it "renders google tag manager index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/analytics/google-tag-manager"
    expect(response.status).to eq(200)
  end

  it "renders conversations index and show" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/transactions-and-reviews/view-conversations"
    expect(response.status).to eq(200)

    get "http://#{@domain}/ja/admin/transactions-and-reviews/view-conversations/#{@conversation.id}"
    expect(response.status).to eq(200)
  end

  it "renders plans show (redirect or not-found from plan service)" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/plan"
    expect([200, 302, 404]).to include(response.status)
  end

  it "renders user fields new and edit popups (JS)" do
    field = FactoryBot.create(:custom_dropdown_field, community: @community, entity_type: "for_person")
    admin_sign_in

    get "http://#{@domain}/ja/admin/users/user-fields/new",
        params: { field_type: "DropdownField" }, xhr: true
    expect(response.status).to eq(200)

    get "http://#{@domain}/ja/admin/users/user-fields/#{field.id}/edit", xhr: true
    expect(response.status).to eq(200)
  end
end
