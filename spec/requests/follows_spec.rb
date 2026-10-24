# frozen_string_literal: true

require 'spec_helper'

# 人物フォロー（followers）/ フォロー一覧（followed_people）のカバレッジ
describe "Follows", type: :request do

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

    @domain = "follows-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @follower = FactoryBot.create(:person, username: "followactor", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @follower, community: @community)
    @target = FactoryBot.create(:person, username: "followtarget", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @target, community: @community)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "follows and unfollows a person" do
    t = UserService::API::AuthTokens.create_login_token(@follower.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
    expect(response.status).to eq(302)

    post "http://#{@domain}/ja/#{@target.username}/followers",
         headers: { "HTTP_REFERER" => "http://#{@domain}/ja/#{@target.username}" }
    expect(response).to have_http_status(:redirect)
    expect(@target.reload.followers).to include(@follower)

    delete "http://#{@domain}/ja/#{@target.username}/followers/#{@follower.id}",
           headers: { "HTTP_REFERER" => "http://#{@domain}/ja/#{@target.username}" }
    expect(@target.reload.followers).not_to include(@follower)
  end

  it "lists followed people for the signed-in user (JS format)" do
    @target.followers << @follower

    t = UserService::API::AuthTokens.create_login_token(@follower.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"

    # index は HTML を 406 で返す設計のため JS(XHR)で取得する
    get "http://#{@domain}/ja/#{@follower.username}/followed_people", xhr: true

    expect(response.status).to eq(200)
  end
end
