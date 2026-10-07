# frozen_string_literal: true

require 'spec_helper'

# 無料取引フロー（free_transactions#contact/create_contact）と
# 下書き承認会話（accept_preauthorized_conversations）のカバレッジ
describe "Free transaction and preauthorized flows", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "free-flows.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @author = FactoryBot.create(:person, username: "freeauthor", community_id: @community.id, member_of: @community)
    @buyer = FactoryBot.create(:person, username: "freebuyer", community_id: @community.id, member_of: @community)
    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @author)
  end

  def sign_in(person)
    t = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  # ---- free_transactions ----

  it "renders the contact form for a buyer" do
    sign_in(@buyer)
    get "http://#{@domain}/ja/listings/#{@listing.id}/contact"
    expect(response.status).to eq(200)
  end

  it "creates a free transaction from the contact form" do
    sign_in(@buyer)
    expect {
      post "http://#{@domain}/ja/listings/#{@listing.id}/create_contact",
           params: { listing_conversation: { content: "この無料出品に興味があります" } }
    }.to change(Transaction, :count).by(1)
    expect(response).to have_http_status(:redirect)
  end

  it "blocks authors from contacting their own listing" do
    sign_in(@author)
    get "http://#{@domain}/ja/listings/#{@listing.id}/contact"
    expect(response).to have_http_status(:redirect)
  end

  it "blocks contact on closed listings" do
    closed = FactoryBot.create(:listing, community_id: @community.id, author: @author)
    closed.update_column(:open, false)
    sign_in(@buyer)
    get "http://#{@domain}/ja/listings/#{closed.id}/contact"
    expect(response).to have_http_status(:redirect)
  end

  # ---- accept_preauthorized_conversations ----

  def create_tx(state)
    conversation = FactoryBot.create(:conversation, community: @community)
    FactoryBot.create(:participation, conversation: conversation, person: @author, is_starter: true)
    FactoryBot.create(:participation, conversation: conversation, person: @buyer, is_starter: false)
    FactoryBot.create(:transaction,
                      community: @community,
                      listing: @listing,
                      starter: @buyer,
                      listing_author: @author,
                      conversation: conversation,
                      current_state: state,
                      payment_gateway: "stripe")
  end

  it "redirects non-authors away from accept" do
    tx = create_tx(:preauthorized)
    sign_in(@buyer)
    get "http://#{@domain}/ja/#{@buyer.username}/messages/#{tx.id}/accept_preauthorized"
    expect(response).to have_http_status(:redirect)
  end

  it "redirects authors when the transaction is not preauthorized" do
    tx = create_tx(:initiated)
    sign_in(@author)
    get "http://#{@domain}/ja/#{@author.username}/messages/#{tx.id}/accept_preauthorized"
    expect(response).to have_http_status(:redirect)
  end

  it "redirects authors when rejecting a non-preauthorized transaction" do
    tx = create_tx(:initiated)
    sign_in(@author)
    get "http://#{@domain}/ja/#{@author.username}/messages/#{tx.id}/reject_preauthorized"
    expect(response).to have_http_status(:redirect)
  end
end
