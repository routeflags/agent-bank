# frozen_string_literal: true

require 'spec_helper'

# マイページのウォレット残高表示（Issue #58）の描画ガード:
# - 本人のページにのみ残高（3桁区切り）とチャージボタンが出る
# - 他人のページ・未ログインでは残高もボタンも出ない
# - 表示は読み取り専用（ウォレット行を作らない）
describe "Mypage wallet", type: :request do
  before do
    skip "webpack ビルド成果物（app/assets/webpack）が無いため" unless webpack_assets_available?
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "mypage-wallet.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @community.reload

    @owner = FactoryBot.create(:person, username: "walletowner", community_id: @community.id)
    @other = FactoryBot.create(:person, username: "walletviewer", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @owner, community: @community)
    FactoryBot.create(:community_membership, person: @other, community: @community)

    FactoryBot.create(:listing, community_id: @community.id, author: @owner, title: "Owner persona")
    FactoryBot.create(:listing, community_id: @community.id, author: @other, title: "Other persona")
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  # 会話一覧 spec と同じ流儀: auth トークンでセッションを確立してから描画する。
  def login_as(person)
    token = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja/#{person.username}?auth=#{token}"
    expect(response.status).to eq(302)
  end

  def owner_page
    "http://#{@domain}/ja/#{@owner.username}"
  end

  it "本人のページに残高（3桁区切り）とチャージボタンを表示する" do
    FactoryBot.create(:wallet, person: @owner, community: @community, balance_cents: 6020)
    login_as(@owner)

    get owner_page

    expect(response.status).to eq(200)
    expect(response.body).to include(I18n.t("lamprey.mypage.wallet_balance_label"))
    expect(response.body).to include("¥6,020")
    expect(response.body).to include(I18n.t("lamprey.mypage.wallet_charge"))
    expect(response.body).to include("MypageWalletApp")
  end

  it "他人のページには残高もチャージボタンも出さない" do
    FactoryBot.create(:wallet, person: @owner, community: @community, balance_cents: 6020) unless Wallet.exists?(person_id: @owner.id, community_id: @community.id)
    login_as(@owner)

    get "http://#{@domain}/ja/#{@other.username}"

    expect(response.status).to eq(200)
    expect(response.body).not_to include(I18n.t("lamprey.mypage.wallet_balance_label"))
    expect(response.body).not_to include(I18n.t("lamprey.mypage.wallet_charge"))
    expect(response.body).not_to include("MypageWalletApp")
  end

  it "未ログインの閲覧では残高もチャージボタンも出さない" do
    get owner_page

    expect(response.status).to eq(200)
    expect(response.body).not_to include(I18n.t("lamprey.mypage.wallet_balance_label"))
    expect(response.body).not_to include("MypageWalletApp")
  end

  it "ウォレットが無い本人の表示では0円を出し、ウォレット行を作らない" do
    Wallet.where(person_id: @owner.id, community_id: @community.id).delete_all
    login_as(@owner)

    expect { get owner_page }.not_to change(Wallet, :count)

    expect(response.status).to eq(200)
    expect(response.body).to include(I18n.t("lamprey.mypage.wallet_balance_label"))
    expect(response.body).to include("¥0")
  end
end
