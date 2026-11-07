# frozen_string_literal: true

require "spec_helper"

# Issue #148 第 2 段: マイページの「ペルソナ利用履歴」に実行経路（Web / MCP）を出す。
#
# 経路の正本は `chat_sessions.channel`（#144 で追加）。DB の既定値は web なので、
# 既存行とブラウザからのチャットは Web、MCP クライアント（実行 API）は MCP と
# 表示される。ビューは未知の値を Web に倒すので、値が増えても表は壊れない。
describe "設定の取引画面（ペルソナ利用履歴の実行経路）", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "usage-channel.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @community.reload

    @seller = FactoryBot.create(:person, username: "channelseller",
                                         display_name: "経路を確認する出品者",
                                         community_id: @community.id)
    FactoryBot.create(:community_membership, person: @seller, community: @community)

    @listing = FactoryBot.create(:listing, community_id: @community.id,
                                           author: @seller,
                                           title: "経路を確認するスキル")

    # 同じ出品に対する 2 人の利用者。1 人はブラウザ（web）、1 人は MCP。
    browser_user = FactoryBot.create(:person, username: "browseruser",
                                              display_name: "ブラウザの利用者",
                                              community_id: @community.id)
    mcp_user = FactoryBot.create(:person, username: "mcpuser",
                                          display_name: "MCP の利用者",
                                          community_id: @community.id)

    FactoryBot.create(:chat_session, person_id: browser_user.id,
                                     listing_id: @listing.id, channel: "web")
    FactoryBot.create(:chat_session, person_id: mcp_user.id,
                                     listing_id: @listing.id, channel: "mcp")
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def sign_in_as_seller
    token = UserService::API::AuthTokens.create_login_token(@seller.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  def usage_page
    sign_in_as_seller
    get "http://#{@domain}/ja/#{@seller.username}/settings/transactions"
    expect(response.status).to eq(200)
  end

  # 表のヘッダー（表示中の文言）を取り出す。
  def header_labels
    Nokogiri::HTML(response.body).css("table.raku-table thead th").map { |th| th.text.strip }
  end

  # 利用者名 => 経路列の文字列。列の位置に依存せず、ヘッダーの並びから引く。
  def route_by_user
    headers = header_labels
    user_index = headers.index(I18n.t("lamprey.mypage.skill_usage_th_user", locale: :ja))
    route_index = headers.index(I18n.t("lamprey.mypage.skill_usage_th_route", locale: :ja))

    Nokogiri::HTML(response.body).css("table.raku-table tbody tr").to_h do |row|
      cells = row.css("td").map { |td| td.text.strip }
      [cells[user_index], cells[route_index]]
    end
  end

  it "経路の列見出しが出る" do
    usage_page

    expect(header_labels).to include(I18n.t("lamprey.mypage.skill_usage_th_route", locale: :ja))
  end

  it "ブラウザからの利用は Web、MCP からの利用は MCP と出る" do
    usage_page

    expect(route_by_user).to eq(
      "MCP の利用者" => I18n.t("lamprey.mypage.skill_usage_route_mcp", locale: :ja),
      "ブラウザの利用者" => I18n.t("lamprey.mypage.skill_usage_route_web", locale: :ja)
    )
  end

  it "経路は課金額の後ろ（最後の列）にあり、既存の列順を変えない" do
    usage_page

    headers = header_labels
    expect(headers.last).to eq(I18n.t("lamprey.mypage.skill_usage_th_route", locale: :ja))
    expect(headers.first).to eq(I18n.t("lamprey.mypage.skill_usage_th_datetime", locale: :ja))
  end

  it "未知の channel でも Web として表示して表を壊さない" do
    usage_page
    headers = header_labels
    route_index = headers.index(I18n.t("lamprey.mypage.skill_usage_th_route", locale: :ja))
    before_rows = Nokogiri::HTML(response.body).css("table.raku-table tbody tr").size

    ChatSession.where(listing_id: @listing.id, channel: "mcp").update_all(channel: "future-value")

    usage_page
    rows = Nokogiri::HTML(response.body).css("table.raku-table tbody tr")
    expect(rows.size).to eq(before_rows)
    expect(rows.map { |row| row.css("td")[route_index].text.strip }.uniq)
      .to eq([I18n.t("lamprey.mypage.skill_usage_route_web", locale: :ja)])
  ensure
    ChatSession.where(listing_id: @listing.id).update_all(channel: "web")
  end
end
