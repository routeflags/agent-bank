# frozen_string_literal: true

require "spec_helper"

# Issue #70: マイページの出品中スキル表に公開/非公開の切り替えタブ。
describe "マイページの公開/非公開タブ", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "mypage-tabs.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @category = FactoryBot.create(:category, community: @community)
    @category.translation_attributes = { ja: { name: "タブ検証" } }
    @category.save!

    @person = FactoryBot.create(:person, username: "tabowner", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)

    @open_listing = FactoryBot.create(:listing, community_id: @community.id,
                                                category: @category,
                                                author: @person,
                                                title: "公開中の出品",
                                                price_cents: 1000)
    @closed_listing = FactoryBot.create(:listing, community_id: @community.id,
                                                  category: @category,
                                                  author: @person,
                                                  title: "非公開の出品",
                                                  price_cents: 1000,
                                                  open: false)
    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def sign_in
    token = UserService::API::AuthTokens.create_login_token(@person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  it "本人のマイページに公開/非公開のタブが並ぶ" do
    sign_in
    get "http://#{@domain}/ja/#{@person.username}"

    expect(response.status).to eq(200)
    doc = Nokogiri::HTML(response.body)
    tabs = doc.css(".raku-table-title").first&.previous_element
    expect(response.body).to include("raku-featured__tabs")
    expect(response.body).to include("?show_closed=true")

    active = doc.css(".raku-featured__tab.is-active").map { |tab| tab.text.strip }
    expect(active).to eq([I18n.t("lamprey.mypage.tab_open", locale: :ja)])
  end

  it "既定タブは公開中のみを出し、非公開は出さない" do
    sign_in
    get "http://#{@domain}/ja/#{@person.username}"

    expect(response.body).to include("公開中の出品")
    expect(response.body).not_to include("非公開の出品")
  end

  it "show_closed=true で非公開のみを出す（公開中は混ざらない）" do
    sign_in
    get "http://#{@domain}/ja/#{@person.username}?show_closed=true"

    expect(response.status).to eq(200)
    expect(response.body).to include("非公開の出品")
    expect(response.body).not_to include("公開中の出品")

    doc = Nokogiri::HTML(response.body)
    active = doc.css(".raku-featured__tab.is-active").map { |tab| tab.text.strip }
    expect(active).to eq([I18n.t("lamprey.mypage.tab_closed", locale: :ja)])
  end

  it "他人のマイページにはタブを出さない" do
    other = FactoryBot.create(:person, username: "tabviewer", community_id: @community.id)
    FactoryBot.create(:community_membership, person: other, community: @community)
    token = UserService::API::AuthTokens.create_login_token(other.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"

    get "http://#{@domain}/ja/#{@person.username}"

    expect(response.status).to eq(200)
    # サイドバーの「出品管理」リンクは全員に出すので、タブの有無で判定する。
    doc = Nokogiri::HTML(response.body)
    expect(doc.css(".raku-featured__tab").size).to eq(0)
    expect(response.body).not_to include("非公開の出品")
  end
end
