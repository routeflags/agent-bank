# frozen_string_literal: true

require 'spec_helper'

# Issue #106 Phase 1: 出品（ペルソナ）評価の投稿
# POST /:locale/listings/:listing_id/testimonials
describe 'Listing testimonials', type: :request do
  # test 環境は allow_forgery_protection=true のため、POST は CSRF トークンなしで
  # 拒否される。このファイルの example のみ無効化する。
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = 'listing-reviews.custom.org'
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { 'locales' => ['ja'] })
    @community.reload

    @seller = FactoryBot.create(:person, username: 'reviewseller', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @seller, community: @community)
    @reviewer = FactoryBot.create(:person, username: 'reviewer', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @reviewer, community: @community)
    @quiet_reviewer = FactoryBot.create(:person, username: 'quietreviewer', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @quiet_reviewer, community: @community)
    @newcomer = FactoryBot.create(:person, username: 'nonewcomer', community_id: @community.id)
    FactoryBot.create(:community_membership, person: @newcomer, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @seller,
                                           title: '評価対象のペルソナ',
                                           default_run_mode: 'run_online')
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def sign_in(person)
    token = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
    expect(response.status).to eq(302)
  end

  def session_with_reply(person, listing = @listing)
    session = FactoryBot.create(:chat_session, listing: listing, person_id: person.id)
    FactoryBot.create(:chat_message, chat_session: session, role: 'assistant', seq: 2)
    session
  end

  def session_without_reply(person, listing = @listing)
    session = FactoryBot.create(:chat_session, listing: listing, person_id: person.id)
    FactoryBot.create(:chat_message, chat_session: session, role: 'user', seq: 1)
    session
  end

  def post_review(stars: 5, text: 'とても良いペルソナでした')
    post "http://#{@domain}/ja/listings/#{@listing.id}/testimonials",
         params: { testimonial: { stars: stars, text: text } }
  end

  it 'AI 応答を受け取った利用者は評価できる（出品者に紐づく）' do
    session_with_reply(@reviewer)
    sign_in(@reviewer)

    expect { post_review(stars: 5, text: 'よかったです') }.to change(Testimonial, :count).by(1)

    review = Testimonial.last
    expect(review.listing_id).to eq(@listing.id)
    expect(review.author_id).to eq(@reviewer.id)
    expect(review.receiver_id).to eq(@seller.id)
    expect(review.transaction_id).to be_nil
    expect(review.grade).to eq(1.0)
    expect(review.text).to eq('よかったです')

    expect(flash[:notice]).to eq(I18n.t('layouts.notifications.listing_review_thanks', locale: :ja))
    expect(response).to redirect_to(%r{/ja/listings/#{@listing.id}})
  end

  it '同じ人が 2 回目は投稿できない' do
    session_with_reply(@reviewer)
    sign_in(@reviewer)
    post_review

    expect { post_review }.not_to change(Testimonial, :count)
    expect(flash[:error]).to eq(I18n.t('layouts.notifications.listing_review_already_given', locale: :ja))
    expect(response).to redirect_to(%r{/ja/listings/#{@listing.id}})
  end

  it '出品者本人は投稿できない' do
    session_with_reply(@seller)
    sign_in(@seller)

    expect { post_review }.not_to change(Testimonial, :count)
    expect(flash[:error]).to eq(I18n.t('layouts.notifications.listing_review_own_listing', locale: :ja))
  end

  it 'AI 応答のないセッションしか無ければ投稿できない' do
    session_without_reply(@quiet_reviewer)
    sign_in(@quiet_reviewer)

    expect { post_review }.not_to change(Testimonial, :count)
    expect(flash[:error]).to eq(I18n.t('layouts.notifications.listing_review_not_eligible', locale: :ja))
  end

  it 'チャット履歴が無ければ投稿できない' do
    sign_in(@newcomer)

    expect { post_review }.not_to change(Testimonial, :count)
    expect(flash[:error]).to eq(I18n.t('layouts.notifications.listing_review_not_eligible', locale: :ja))
  end

  it '未ログインはログイン画面へリダイレクトされる' do
    expect { post_review }.not_to change(Testimonial, :count)
    expect(response.status).to eq(302)
    expect(response.location).to include('/login')
  end

  it '本文が空でも評価できる（grade は星から換算）' do
    session_with_reply(@reviewer)
    sign_in(@reviewer)

    expect { post_review(stars: 3, text: '') }.to change(Testimonial, :count).by(1)
    expect(Testimonial.last.grade).to eq(0.5)
    expect(Testimonial.last.text).to be_blank
  end

  it '星が範囲外（6）なら保存しない' do
    session_with_reply(@reviewer)
    sign_in(@reviewer)

    expect { post_review(stars: 6) }.not_to change(Testimonial, :count)
    expect(flash[:error]).to eq(I18n.t('layouts.notifications.listing_review_failed', locale: :ja))
  end

  it '本文が 1000 文字を超えると保存しない' do
    session_with_reply(@reviewer)
    sign_in(@reviewer)

    expect { post_review(text: 'あ' * (Testimonial::TEXT_MAX_LENGTH + 1)) }
      .not_to change(Testimonial, :count)
    expect(flash[:error]).to eq(I18n.t('layouts.notifications.listing_review_failed', locale: :ja))
  end

  it '星 1〜5 が grade 0..1 に正しく換算されて保存される' do
    { 1 => 0.0, 2 => 0.25, 3 => 0.5, 4 => 0.75, 5 => 1.0 }.each do |stars, expected_grade|
      person = FactoryBot.create(:person, username: "star#{stars}", community_id: @community.id)
      FactoryBot.create(:community_membership, person: person, community: @community)
      session_with_reply(person)
      sign_in(person)

      expect { post_review(stars: stars) }.to change(Testimonial, :count).by(1)
      expect(Testimonial.last.grade).to eq(expected_grade)
      expect(Testimonial.last.displayed_grade).to eq(stars)
    end
  end
end
