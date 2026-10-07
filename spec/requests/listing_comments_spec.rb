# frozen_string_literal: true

require 'spec_helper'

# 出品へのコメント投稿（comments#create）のカバレッジ
describe "Listing comments", type: :request do

  # test 環境は allow_forgery_protection=true のため、リクエストスペックの
  # POST は CSRF トークンなしで拒否される。このファイルの例のみ無効化する。
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end
  before(:all) do
    DatabaseCleaner.start

    @domain = "comments-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] }, listing_comments_in_use: true)
    @community.reload

    @author = FactoryBot.create(:person, username: "commentauthor", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @author, community: @community)
    @commenter = FactoryBot.create(:person, username: "commenter", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @commenter, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @author)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def login_as(person)
    t = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
    expect(response.status).to eq(302)
  end

  it "creates a comment for a signed-in participant" do
    login_as(@commenter)

    expect {
      post "http://#{@domain}/ja/listings/#{@listing.id}/comments",
           params: { comment: { content: "Great persona!", listing_id: @listing.id } }
    }.to change(Comment, :count).by(1)

    expect(response).to redirect_to(%r{/ja/listings/#{@listing.id}\z})
  end

  it "redirects anonymous visitors to login" do
    expect {
      post "http://#{@domain}/ja/listings/#{@listing.id}/comments",
           params: { comment: { content: "Anonymous" } }
    }.not_to change(Comment, :count)

    expect(response.status).to eq(302)
  end
end
