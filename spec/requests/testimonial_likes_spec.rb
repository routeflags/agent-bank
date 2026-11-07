# frozen_string_literal: true

require 'spec_helper'

# Issue #151: レビューへの「いいね」
# POST / DELETE /:locale/listings/:listing_id/testimonials/:testimonial_id/like
describe 'Testimonial likes', type: :request do
  # test 環境は allow_forgery_protection=true のため、POST / DELETE は CSRF トークン
  # なしで拒否される。このファイルの example のみ無効化する。
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = 'review-likes.custom.org'
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { 'locales' => ['ja'] })
    @community.reload

    @seller = FactoryBot.create(:person, username: 'likeseller', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @seller, community: @community)
    @reviewer = FactoryBot.create(:person, username: 'likereviewer', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @reviewer, community: @community)
    @liker = FactoryBot.create(:person, username: 'likerone', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @liker, community: @community)
    @other_liker = FactoryBot.create(:person, username: 'likertwo', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @other_liker, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @seller,
                                           title: 'いいね対象のペルソナ',
                                           default_run_mode: 'run_online')
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  # レビューは example ごとに作り直す（transaction で巻き戻る）。
  let!(:review) do
    Testimonial.create!(listing: @listing, author: @reviewer, receiver: @seller,
                        grade: 1.0, text: 'とても良かったです')
  end

  def sign_in(person)
    token = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
    expect(response.status).to eq(302)
  end

  def like_url(target = review, listing = @listing)
    "http://#{@domain}/ja/listings/#{listing.id}/testimonials/#{target.id}/like"
  end

  def json_body
    JSON.parse(response.body)
  end

  it 'ログイン済みならいいねでき、件数が返る' do
    sign_in(@liker)

    expect { post like_url, as: :json }.to change(TestimonialLike, :count).by(1)
    expect(response.status).to eq(200)
    expect(json_body).to eq({ 'liked' => true, 'likes_count' => 1 })
    expect(review.reload.likes_count).to eq(1)
  end

  it 'いいねを取り消せる' do
    TestimonialLike.create!(testimonial: review, person: @liker)
    sign_in(@liker)

    expect { delete like_url, as: :json }.to change(TestimonialLike, :count).by(-1)
    expect(response.status).to eq(200)
    expect(json_body).to eq({ 'liked' => false, 'likes_count' => 0 })
    expect(review.reload.likes_count).to eq(0)
  end

  it '二重押しは 200 のままで、件数も増えない（冪等）' do
    sign_in(@liker)
    post like_url, as: :json
    first_response = json_body

    expect { post like_url, as: :json }.not_to change(TestimonialLike, :count)
    expect(response.status).to eq(200)
    expect(json_body).to eq(first_response)
    expect(review.reload.likes_count).to eq(1)
  end

  it '別の利用者も同じレビューにいいねできる' do
    sign_in(@liker)
    post like_url, as: :json

    sign_in(@other_liker)
    expect { post like_url, as: :json }.to change(TestimonialLike, :count).by(1)
    expect(json_body).to eq({ 'liked' => true, 'likes_count' => 2 })
  end

  it '未ログインの Ajax には 401 とログイン URL を JSON で返す' do
    expect { post like_url, as: :json }.not_to change(TestimonialLike, :count)
    expect(response.status).to eq(401)
    expect(json_body['error']).to eq('unauthorized')
    expect(json_body['login_url']).to include('/login')
  end

  it '未ログインの HTML 遷移はログイン画面へリダイレクトする' do
    post like_url

    expect(response.status).to eq(302)
    expect(response.location).to include('/login')
  end

  it '自分のレビューにはいいねできない（403）' do
    sign_in(@reviewer)

    expect { post like_url, as: :json }.not_to change(TestimonialLike, :count)
    expect(response.status).to eq(403)
    expect(review.reload.likes_count).to eq(0)
  end

  it '存在しないレビューは 404' do
    sign_in(@liker)

    post "http://#{@domain}/ja/listings/#{@listing.id}/testimonials/9999999/like", as: :json
    expect(response.status).to eq(404)
  end

  it '別の出品の URL からは、そのレビューにいいねできない（404）' do
    other_listing = FactoryBot.create(:listing, community_id: @community.id, author: @seller)
    sign_in(@liker)

    post like_url(review, other_listing), as: :json
    expect(response.status).to eq(404)
    expect(review.reload.likes_count).to eq(0)
  end

  it 'いいねは avg_rating / reviews_count に影響しない' do
    @listing.reload
    before_values = @listing.slice(:avg_rating, :reviews_count)
    expect(before_values[:reviews_count]).to eq(1)

    sign_in(@liker)
    post like_url, as: :json
    expect(@listing.reload.slice(:avg_rating, :reviews_count)).to eq(before_values)

    delete like_url, as: :json
    expect(@listing.reload.slice(:avg_rating, :reviews_count)).to eq(before_values)
  end
end
