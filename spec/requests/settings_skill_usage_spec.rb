# frozen_string_literal: true

require "spec_helper"

# Issue #69: 設定の「取引」画面は出品スキルの第三者利用履歴を表示する。
# - 自分の出品に紐づく第三者の利用セッションが出る
# - 出品者本人の利用セッションは出ない
# - 利用が無い場合は空状態が出る
describe "設定の取引画面（出品スキルの第三者利用履歴）", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "skill-usage.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                                settings: { "locales" => ["ja"] })
    @community.reload

    @seller = FactoryBot.create(:person, username: "skillowner",
                                         display_name: "出品者の表示名",
                                         community_id: @community.id)
    FactoryBot.create(:community_membership, person: @seller, community: @community)

    @buyer = FactoryBot.create(:person, username: "skilluser",
                                        display_name: "利用者の表示名",
                                        community_id: @community.id)
    FactoryBot.create(:community_membership, person: @buyer, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id,
                                           author: @seller,
                                           title: "第三者利用されるスキル")

    # 第三者の利用セッション（メッセージ2件・合計 12,345 トークン）
    third_party_session = FactoryBot.create(:chat_session, person_id: @buyer.id, listing_id: @listing.id)
    FactoryBot.create(:chat_message, chat_session: third_party_session, role: "user", seq: 1,
                                     input_tokens: 12_000, output_tokens: 0)
    FactoryBot.create(:chat_message, chat_session: third_party_session, role: "assistant", seq: 2,
                                     input_tokens: 0, output_tokens: 345)

    # 出品者本人の利用セッション（除外される）
    self_session = FactoryBot.create(:chat_session, person_id: @seller.id, listing_id: @listing.id)
    FactoryBot.create(:chat_message, chat_session: self_session, role: "user", seq: 1,
                                     input_tokens: 10, output_tokens: 0)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def sign_in_as_seller
    token = UserService::API::AuthTokens.create_login_token(@seller.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  def usage_rows
    Nokogiri::HTML(response.body).css("table.raku-table tbody tr")
  end

  # 利用者列（3列目）の表示名だけを取り出す。
  # ヘッダーのユーザーメニューにはログイン中ユーザー（出品者）の表示名が
  # 出るため、全文検索ではなく表の行に絞って検証する。
  def usage_user_names
    usage_rows.map { |row| row.css("td")[2].text.strip }
  end

  it "第三者の利用セッションが1行で出る" do
    sign_in_as_seller
    get "http://#{@domain}/ja/#{@seller.username}/settings/transactions"

    expect(response.status).to eq(200)
    expect(response.body).to include("第三者利用されるスキル")
    expect(response.body).to include("利用者の表示名")
    expect(response.body).to include("12,345")
    expect(usage_rows.size).to eq(1)
  end

  it "出品者本人の利用は出ない" do
    sign_in_as_seller
    get "http://#{@domain}/ja/#{@seller.username}/settings/transactions"

    expect(response.status).to eq(200)
    expect(usage_rows.size).to eq(1)
    expect(usage_user_names).to eq(["利用者の表示名"])
  end

  it "利用が無い出品者は空状態が出る" do
    lonely = FactoryBot.create(:person, username: "lonelyseller",
                                        display_name: "誰にも使われていない出品者",
                                        community_id: @community.id)
    FactoryBot.create(:community_membership, person: lonely, community: @community)
    token = UserService::API::AuthTokens.create_login_token(lonely.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"

    get "http://#{@domain}/ja/#{lonely.username}/settings/transactions"

    expect(response.status).to eq(200)
    expect(response.body).to include(I18n.t("lamprey.mypage.skill_usage_empty", locale: :ja))
  end
end
