# frozen_string_literal: true

require 'spec_helper'

# admin2/design 配下（display / cover-photos）と social-media/image-and-tags のカバレッジ
describe "Admin2 design settings", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-design.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @customization = @community.community_customizations.find_or_create_by(locale: "ja")
    @admin = FactoryBot.create(:person, username: "admin2design",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  # display (arrangement)
  it "renders display index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/design/arrangement"
    expect(response.status).to eq(200)
  end

  it "updates display settings" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/design/arrangement/update_display",
          params: { community: { show_category_in_listing_list: true } }
    expect(response.status).to eq(200)
    expect(@community.reload.show_category_in_listing_list).to eq(true)
  end

  it "returns unprocessable on invalid display params" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/design/arrangement/update_display", params: {}
    expect(response.status).to eq(422)
  end

  # cover photos
  it "renders cover photos index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/design/cover-photos"
    expect(response.status).to eq(200)
  end

  it "updates cover photos (JS response)" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/design/cover-photos/update_cover_photos",
          params: { community: { small_cover_photo: "" } }, xhr: true
    expect(response.status).to eq(200)
  end

  # social media image tags
  it "renders image tags index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/social-media/image-and-tags"
    expect(response.status).to eq(200)
  end

  it "updates social media image tags" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/social-media/image-and-tags/update_image",
          params: {
            community: {
              community_customizations_attributes: [
                { id: @customization.id, social_media_title: "SNS用タイトル" }
              ]
            }
          }, xhr: true
    expect(response.status).to eq(200)
    expect(@customization.reload.social_media_title).to eq("SNS用タイトル")
  end
end
