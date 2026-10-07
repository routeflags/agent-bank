# frozen_string_literal: true

require 'spec_helper'

# 取引へのレビュー投稿（testimonials#create）のカバレッジ
describe "Testimonials", type: :request do

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

    @domain = "testimonials-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @seller = FactoryBot.create(:person, username: "tseller", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @seller, community: @community)
    @buyer = FactoryBot.create(:person, username: "tbuyer", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @buyer, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @seller)
    @transaction = FactoryBot.create(:transaction,
                                      community: @community,
                                      listing: @listing,
                                      starter: @buyer,
                                      listing_author: @seller,
                                      current_state: :completed)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "creates a testimonial for the transaction counterpart" do
    t = UserService::API::AuthTokens.create_login_token(@buyer.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
    expect(response.status).to eq(302)

    expect {
      post "http://#{@domain}/ja/#{@buyer.username}/messages/#{@transaction.id}/feedbacks",
           params: { testimonial: { text: "優れたペルソナでした", grade: 1 } }
    }.to change(Testimonial, :count).by(1)

    expect(response).to redirect_to(person_transaction_path(person_id: @buyer.id, id: @transaction.id))
    testimonial = Testimonial.last
    expect(testimonial.author).to eq(@buyer)
    expect(testimonial.receiver).to eq(@seller)
  end
end
