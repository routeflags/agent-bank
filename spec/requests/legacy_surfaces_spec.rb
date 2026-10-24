# frozen_string_literal: true

require 'spec_helper'

# レガシー/周辺サーフェス（email_design / mercury images / admin2 order-types）のカバレッジ
describe "Legacy and peripheral surfaces", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "legacy-surfaces.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "legacysurface",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  # email_design#show — 任意テンプレート描画
  it "renders an email design preview page" do
    get "http://#{@domain}/test_design/email"
    expect(response.status).to eq(200)
  end

  # mercury/images#create — 画像JSON API
  it "responds to image create JSON" do
    post "http://#{@domain}/mercury/images.json", params: { image: { image: "invalid" } }, as: :json
    expect(response.status).to eq(422)
  end

  # admin2 order-types
  def seed_shape
    process = FactoryBot.create(:transaction_process, community_id: @community.id, process: 'none', author_is_seller: true)
    result = ShapeService.new([process]).create(
      community: @community,
      default_locale: "ja",
      opts: {
        action_button_label: { "ja" => "申し込む" },
        name: { "ja" => "注文タイプ" },
        author_is_seller: true
      }
    )
    result.data
  end

  it "renders order types index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/listings/order-types"
    expect(response.status).to eq(200)
  end

  it "renders new order type form from a template (JS)" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/listings/order-types/new",
        params: { type_id: "selling_products" }, xhr: true
    expect(response.status).to eq(200)
  end

  it "renders add_unit JS partial" do
    admin_sign_in
    post "http://#{@domain}/ja/admin/listings/order-types/add_unit",
         params: {
           unit_label: { "ja" => "時間" },
           selector_label: { "ja" => "単位" },
           unit_type: "custom"
         }, xhr: true
    expect(response.status).to eq(200)
  end

  it "renders edit form for an existing order type (JS)" do
    shape = seed_shape
    admin_sign_in
    get "http://#{@domain}/ja/admin/listings/order-types/#{shape.id}/edit", xhr: true
    expect(response.status).to eq(200)
  end
end
