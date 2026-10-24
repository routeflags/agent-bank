# frozen_string_literal: true

require 'spec_helper'

# 取引ページ（transactions#show）のカバレッジ — 参加者のみ閲覧可
describe "Transaction page", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "transaction-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @seller = FactoryBot.create(:person, username: "txseller", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @seller, community: @community)
    @buyer = FactoryBot.create(:person, username: "txbuyer", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @buyer, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @seller)
    @conversation = FactoryBot.create(:conversation, community: @community)
    FactoryBot.create(:participation, conversation: @conversation, person: @seller, is_starter: true)
    FactoryBot.create(:participation, conversation: @conversation, person: @buyer, is_starter: false)
    FactoryBot.create(:message, conversation: @conversation, sender: @buyer, content: "取引に関する連絡")
    @transaction = FactoryBot.create(:transaction,
                                      community: @community,
                                      listing: @listing,
                                      starter: @buyer,
                                      listing_author: @seller,
                                      conversation: @conversation,
                                      current_state: :initiated)
    FactoryBot.create(:transaction_transition,
                       tx: @transaction,
                       to_state: "initiated",
                       most_recent: true)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def login_as(person)
    t = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
    expect(response.status).to eq(302)
  end

  it "renders the transaction page for the seller (listing author)" do
    login_as(@seller)

    get "http://#{@domain}/ja/#{@seller.username}/transactions/#{@transaction.id}"

    expect(response.status).to eq(200)
  end

  it "renders the transaction page for the buyer (starter)" do
    login_as(@buyer)

    get "http://#{@domain}/ja/#{@buyer.username}/transactions/#{@transaction.id}"

    expect(response.status).to eq(200)
  end

  it "redirects non-participants away" do
    stranger = FactoryBot.create(:person, username: "txstranger", community_id: @community.id)
    FactoryBot.create(:community_membership, person: stranger, community: @community)
    login_as(stranger)

    get "http://#{@domain}/ja/#{@seller.username}/transactions/#{@transaction.id}"

    expect(response).to redirect_to(%r{\Ahttp://#{@domain}/\z})
  end
end
