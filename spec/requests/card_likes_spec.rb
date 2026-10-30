# frozen_string_literal: true

require "spec_helper"

# Issue #129: カードの星の代わりに実際のいいね数（listing_followers）を出す。
#
# - トップ/一覧のカードに「♡ N」（実データ）が出る
# - タイトル横の ♡ 操作で follow/unfollow でき、同じページに戻る
# - 未ログインの ♡ はログイン画面へのリンク
describe "カードのいいね", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "card-likes.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @category = FactoryBot.create(:category, community: @community)
    @category.translation_attributes = { ja: { name: "いいね検証" } }
    @category.save!

    @author = FactoryBot.create(:person, username: "likeauthor", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @author, community: @community)
    @viewer = FactoryBot.create(:person, username: "likeviewer", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @viewer, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id, category: @category,
                                           author: @author, title: "いいね対象の出品", price_cents: 1000)
    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def sign_in_as(person)
    token = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  it "カードに実データのいいね数が出る" do
    sign_in_as(@viewer)
    get "http://#{@domain}/ja"

    expect(response.status).to eq(200)
    expect(response.body).to include("♡ 0")
    expect(response.body).not_to include("★")
  end

  it "♡ 操作で follow し、同じページに戻る" do
    sign_in_as(@viewer)

    post "http://#{@domain}/ja/listings/#{@listing.to_param}/follow", params: { return_to: "/ja" }
    expect(response.status).to eq(302)
    expect(response.headers["Location"]).to end_with("/ja")
    expect(@listing.reload.followers.count).to eq(1)

    get "http://#{@domain}/ja"
    expect(response.body).to include("♡ 1")
    expect(response.body).to include("fave on")
  end

  it "♡ 操作で unfollow し、同じページに戻る" do
    sign_in_as(@viewer)
    @viewer.follow(@listing)

    delete "http://#{@domain}/ja/listings/#{@listing.to_param}/unfollow", params: { return_to: "/ja" }
    expect(response.status).to eq(302)
    expect(response.headers["Location"]).to end_with("/ja")
    expect(@listing.reload.followers.count).to eq(0)
  end

  it "外部 URL への return_to は出品ページに戻す（オープンリダイレクト防止）" do
    sign_in_as(@viewer)

    post "http://#{@domain}/ja/listings/#{@listing.to_param}/follow", params: { return_to: "https://evil.example/" }
    expect(response.status).to eq(302)
    expect(response.headers["Location"]).not_to include("evil.example")
  end

  it "未ログインの ♡ はログイン画面へのリンク" do
    get "http://#{@domain}/ja"

    expect(response.status).to eq(200)
    expect(response.body).to include("card_login_to_like").or include("いいねするにはログイン")
  end
end
