# frozen_string_literal: true

require 'spec_helper'

# プロフィール描画の回帰ガード:
# - 出品を持つ人物のプロフィールがスキル表つきで200を返す（以前の
#   ListingItem構造体へのメソッド呼び出しによる500を再発防止）
# - 出品なしの人物は空状態を描画する
# - オーナーは show_closed で終了済み出品も含めて表示できる
describe "Profile pages", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "profile-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @seller = FactoryBot.create(:person, username: "sellerprof", community_id: @community.id)
    @buyer  = FactoryBot.create(:person, username: "buyerprof", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @seller, community: @community)
    FactoryBot.create(:community_membership, person: @buyer, community: @community)

    @open_listing = FactoryBot.create(:listing,
                                       community_id: @community.id,
                                       author: @seller,
                                       title: "Seller persona",
                                       times_viewed: 42,
                                       avg_rating: 4.5)
    @closed_listing = FactoryBot.create(:listing,
                                         community_id: @community.id,
                                         author: @seller,
                                         title: "Closed persona",
                                         open: false)
    @other_listing = FactoryBot.create(:listing,
                                        community_id: @community.id,
                                        title: "Someone else's persona")
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "renders the skill table for a person with listings, scoped to that person" do
    get "http://#{@domain}/ja/#{@seller.username}"

    expect(response.status).to eq(200)
    expect(response.body).to include("Seller persona")
    expect(response.body).to include("raku-table__skill-name")
    expect(response.body).not_to include("Someone else's persona")
  end

  it "renders the empty state for a person without listings" do
    get "http://#{@domain}/ja/#{@buyer.username}"

    expect(response.status).to eq(200)
    expect(response.body).to include("raku-table__empty")
    expect(response.body).not_to include("raku-table__skill-name")
  end

  it "hides closed listings from viewers other than the owner" do
    get "http://#{@domain}/ja/#{@seller.username}"

    expect(response.status).to eq(200)
    expect(response.body).not_to include("Closed persona")
  end

  it "returns 404 for unknown usernames instead of raising" do
    get "http://#{@domain}/ja/no_such_user_prof"

    expect(response.status).to eq(404)
  end
end
