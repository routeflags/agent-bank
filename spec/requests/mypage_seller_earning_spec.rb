# frozen_string_literal: true

require 'spec_helper'

# マイページの出品収益「💰 受取」（Issue #59）の描画ガード:
# - 本人のページにのみ累計受取額と直近の受取履歴（出品名・日時・金額）が出る
# - 他人のページ・未ログインでは出ない
# - 表示は読み取り専用（ウォレット行を作らない）
describe "Mypage seller earning", type: :request do
  before do
    skip "webpack ビルド成果物（app/assets/webpack）が無いため" unless webpack_assets_available?
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "mypage-earning.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @community.reload

    @owner = FactoryBot.create(:person, username: "earningowner", community_id: @community.id)
    @other = FactoryBot.create(:person, username: "earningviewer", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @owner, community: @community)
    FactoryBot.create(:community_membership, person: @other, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @owner, title: "Earning persona")
    FactoryBot.create(:listing, community_id: @community.id, author: @other, title: "Other persona")

    @wallet = FactoryBot.create(:wallet, person: @owner, community: @community, balance_cents: 0)
    @usage1 = UsageRecord.create!(input_tokens: 600, output_tokens: 400)
    @usage2 = UsageRecord.create!(input_tokens: 600, output_tokens: 400)
    @wallet.credit_seller_earning!(900, usage_record: @usage1, listing: @listing,
                                        breakdown: { base_cost_cents: 1000, platform_commission_pct: 10,
                                                     platform_commission_cents: 100, seller_payout_cents: 900,
                                                     tokens: 1000 })
    @wallet.credit_seller_earning!(1, usage_record: @usage2, listing: @listing,
                                      breakdown: { base_cost_cents: 1, platform_commission_pct: 10,
                                                   platform_commission_cents: 0, seller_payout_cents: 1,
                                                   tokens: 1000 })
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def login_as(person)
    token = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja/#{person.username}?auth=#{token}"
    expect(response.status).to eq(302)
  end

  def owner_page
    "http://#{@domain}/ja/#{@owner.username}"
  end

  it "本人のページに累計受取額と受取履歴（出品名・金額）を表示する" do
    login_as(@owner)

    get owner_page

    expect(response.status).to eq(200)
    expect(response.body).to include(I18n.t("lamprey.mypage.seller_earning_title"))
    expect(response.body).to include("¥901")
    expect(response.body).to include("Earning persona")
    expect(response.body).to include("¥900")
  end

  it "他人のページには受取情報を出さない" do
    login_as(@owner)

    get "http://#{@domain}/ja/#{@other.username}"

    expect(response.status).to eq(200)
    expect(response.body).not_to include(I18n.t("lamprey.mypage.seller_earning_title"))
    expect(response.body).not_to include("Earning persona")
  end

  it "未ログインの閲覧では受取情報を出さない" do
    get owner_page

    expect(response.status).to eq(200)
    expect(response.body).not_to include(I18n.t("lamprey.mypage.seller_earning_title"))
  end

  it "受取がない本人の表示では空メッセージを出し、ウォレット行を作らない" do
    @wallet.credit_transactions.where(transaction_type: "seller_earning").delete_all
    login_as(@owner)

    expect { get owner_page }.not_to change(Wallet, :count)

    expect(response.status).to eq(200)
    expect(response.body).to include(I18n.t("lamprey.mypage.seller_earning_empty"))
  end
end
