# frozen_string_literal: true

require 'spec_helper'

# 閲覧数の加算（Issue #97）と指標の土台（Issue #98）。
#
# カウンタ変化のみ検証するため、webpack 未ビルド環境の描画成否に依存しない。
#
# - 第三者の通常閲覧で times_viewed が +1 される
# - 出品者本人・bot は数えない
describe "出品の閲覧数加算", type: :request do
  before(:all) do
    DatabaseCleaner.start
    @domain = "listing-stats.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @owner = FactoryBot.create(:person, username: "statsowner", community_id: @community.id)
    @visitor = FactoryBot.create(:person, username: "statsvisitor", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @owner, community: @community)
    FactoryBot.create(:community_membership, person: @visitor, community: @community)
    @community.reload
    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @owner)
  end

  after(:all) do
    DatabaseCleaner.clean
  end


  def listing_page
    "http://#{@domain}/ja/listings/#{@listing.id}"
  end

  def login_as(person)
    token = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  it "第三者の閲覧で times_viewed が 1 増える" do
    login_as(@visitor)
    expect { get listing_page }.to change { @listing.reload.times_viewed }.by(1)
  end

  it "出品者本人の閲覧は数えない" do
    login_as(@owner)
    expect { get listing_page }.not_to(change { @listing.reload.times_viewed })
  end

  it "bot の閲覧は数えない" do
    login_as(@visitor)
    expect {
      get listing_page, headers: { "User-Agent" => "Googlebot/2.1 (+http://www.google.com/bot.html)" }
    }.not_to(change { @listing.reload.times_viewed })
  end
end
