# frozen_string_literal: true

require 'spec_helper'

# admin2/listings/categories（カテゴリ管理）のカバレッジ
describe "Admin2 listing categories", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-categories.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "admin2cats",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)

    # カテゴリ作成には所属 shape が必須のため ShapeService で1件用意する
    process = FactoryBot.create(:transaction_process, community_id: @community.id, process: 'none', author_is_seller: true)
    result = ShapeService.new([process]).create(
      community: @community,
      default_locale: "ja",
      opts: {
        action_button_label: { "ja" => "申し込む" },
        name: { "ja" => "出品" },
        author_is_seller: true
      }
    )
    @shape = result.data
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  def create_category(name)
    FactoryBot.create(:category, community: @community, parent: nil).tap do |c|
      c.translations.create!(locale: "ja", name: name)
    end
  end

  it "renders categories index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/listings/categories"
    expect(response.status).to eq(200)
  end

  it "renders new category form (JS modal)" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/listings/categories/new", xhr: true
    expect(response.status).to eq(200)
  end

  it "creates a category with listing shape" do
    admin_sign_in
    expect {
      post "http://#{@domain}/ja/admin/listings/categories",
           params: {
             category: {
               translation_attributes: { "ja" => { name: "テストカテゴリ" } },
               url: "test-category-#{SecureRandom.hex(3)}",
               listing_shapes: [{ listing_shape_id: @shape.id }]
             }
           }
    }.to change(@community.categories, :count).by(1)
    expect(response).to redirect_to(%r{/ja/admin/listings/categories\z})
  end

  it "renders edit form and updates a category" do
    category = create_category("編集対象")
    admin_sign_in

    get "http://#{@domain}/ja/admin/listings/categories/#{category.id}/edit", xhr: true
    expect(response.status).to eq(200)

    patch "http://#{@domain}/ja/admin/listings/categories/#{category.id}",
          params: {
            category: {
              translation_attributes: { "ja" => { name: "編集済み" } },
              listing_shapes: [{ listing_shape_id: @shape.id }]
            }
          }
    expect(response).to redirect_to(%r{/ja/admin/listings/categories\z})
    expect(category.reload.translations.detect { |t| t.locale == "ja" }&.name).to eq("編集済み")
  end

  it "destroys a category" do
    # can_destroy? はトップレベル2件以上必須（最後の1件は削除不可）のため残すカテゴリを用意
    create_category("残すカテゴリ")
    category = create_category("削除対象")
    admin_sign_in

    expect {
      delete "http://#{@domain}/ja/admin/listings/categories/#{category.id}"
    }.to change(@community.categories, :count).by(-1)
    expect(response).to redirect_to(%r{/ja/admin/listings/categories\z})
  end

  it "reorders categories" do
    c1 = create_category("順序A")
    c2 = create_category("順序B")
    admin_sign_in

    post "http://#{@domain}/ja/admin/listings/categories/order",
         params: { order: [c2.id, c1.id] }
    expect(response.status).to eq(200)
  end

  it "changes category parent (change_category)" do
    parent = create_category("親カテゴリ")
    child = create_category("子カテゴリ")
    admin_sign_in

    post "http://#{@domain}/ja/admin/listings/categories/change_category",
         params: { elem_id: child.id, parent_elem_id: parent.id }
    expect(response.status).to eq(200)
    expect(child.reload.parent_id).to eq(parent.id)
  end

  it "renders remove popup for a category (JS)" do
    category = create_category("削除ポップアップ")
    admin_sign_in

    get "http://#{@domain}/ja/admin/listings/categories/#{category.id}/remove_popup", xhr: true
    expect(response.status).to eq(200)
  end
end
