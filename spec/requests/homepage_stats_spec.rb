# frozen_string_literal: true

require "spec_helper"

# Issue #125: トップの実績サマリーをデザイン正本の 4 指標に合わせる。
#
# 登録エージェント数 / 登録スキル数 / アクティブユーザー / 取引数（累計）を
# **実データのみ** で表示する。デモ数値・ダミー表記は出さない。
describe "トップの実績サマリー", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "homepage-stats.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })

    @category_a = create_category("スキルA")
    @category_b = create_category("スキルB")

    @author = FactoryBot.create(:person, username: "statsowner", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @author, community: @community)

    # 公開中 2 件（カテゴリ A / B）＋ 非公開 1 件（カテゴリ A）
    2.times do |i|
      FactoryBot.create(:listing, community_id: @community.id, category: [@category_a, @category_b][i],
                                  author: @author, title: "公開ペルソナ#{i}", price_cents: 1000)
    end
    FactoryBot.create(:listing, community_id: @community.id, category: @category_a,
                                author: @author, title: "非公開ペルソナ", price_cents: 1000, open: false)

    # 直近のチャット 1 件（assistant 応答あり = 取引 1 件 / アクティブ 1 人）
    listing = Listing.where(community_id: @community.id, open: true).first
    session = FactoryBot.create(:chat_session, listing: listing, person: @author)
    FactoryBot.create(:chat_message, chat_session: session, role: "user", content: "こんにちは",
                                     sender_type: "Person", sender_id: @author.id, seq: 1)
    FactoryBot.create(:chat_message, chat_session: session, role: "assistant", content: "はい",
                                     seq: 2)

    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def create_category(name)
    category = FactoryBot.create(:category, community: @community)
    category.translation_attributes = { ja: { name: name } }
    category.save!
    category
  end

  it "4 指標のラベルを表示する" do
    get "http://#{@domain}/ja"

    expect(response.status).to eq(200)
    body = response.body
    expect(body).to include(I18n.t("lamprey.homepage.stats_agents", locale: :ja))
    expect(body).to include(I18n.t("lamprey.homepage.stats_skills", locale: :ja))
    expect(body).to include(I18n.t("lamprey.homepage.stats_active_users", locale: :ja))
    expect(body).to include(I18n.t("lamprey.homepage.stats_transactions", locale: :ja))
  end

  it "実データの集計値を表示する（デモ数値は出さない）" do
    get "http://#{@domain}/ja"

    doc = Nokogiri::HTML(response.body)
    values = doc.css(".raku-stats__value").map { |node| node.text.strip }
    # 公開中 2 / スキル分類 2 / 直近30日の利用者 1 / 取引 1
    expect(values).to eq(%w[2 2 1 1])
    expect(response.body).not_to include("デモ数値")
  end
end
