require "spec_helper"

# Issue #26: /browse のページ送りでトップページへ戻ってしまうバグの回帰テスト。
#
# - /browse 上のページ送り（will_paginate・無限スクロール pageless）は
#   /browse のまま、絞り込みパラメータ（q / category）も保持される
# - トップ（/）のページ送りは従来どおりトップのまま
describe "一覧ページのページネーションリンク", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "browse-pagination.custom.org"
    # 先頭を en（デフォルトロケール）にして、/ja が非デフォルトロケールの
    # トップ（/ja/）として生成・検証できるようにする。
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["en", "ja"] })
    @category = FactoryBot.create(:category, community: @community)
    @category.translation_attributes = { en: { name: "Piano Category" } }
    @category.save!

    2.times do |i|
      FactoryBot.create(:listing, community_id: @community.id,
                                  category: @category,
                                  title: "Piano lesson #{i}")
    end
    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  before do
    # 既定は 24 件/ページ。1 件/ページにして 2 ページ分の検索結果を作る。
    allow(APP_CONFIG).to receive(:grid_listings_limit).and_return(1)
  end

  # pageless（無限スクロール）に渡す URL を取り出す。
  def pageless_url
    json = response.body[/\.pageless\((\{.*?\})\);/m, 1]
    expect(json).not_to be_nil, "pageless の初期化 JS が見つかりません"
    JSON.parse(json).fetch("url")
  end

  it "/ja/browse のページャ・無限スクロールは /browse のまま絞り込みを保持する" do
    get "http://#{@domain}/ja/browse?q=piano&category=#{@category.url}"

    # リダイレクトされず /browse を直接レンダリングすること
    expect(response.status).to eq(200)

    doc = Nokogiri::HTML(response.body)
    next_link = doc.at_css('a[rel="next"]')
    expect(next_link).not_to be_nil
    expect(next_link["href"]).to start_with("/ja/browse?")
    expect(next_link["href"]).to include("q=piano")
    expect(next_link["href"]).to include("category=#{@category.url}")
    expect(next_link["href"]).to include("page=2")
    # locale はパス段（/ja/browse）で表現し、クエリへ重複させない
    expect(next_link["href"]).not_to include("locale=")

    url = pageless_url
    expect(url).to start_with("/ja/browse?")
    expect(url).to include("q=piano")
    expect(url).to include("category=#{@category.url}")
    expect(url).not_to include("locale=")
    expect(url).not_to include("page=") # pageless は page なしへ送る
  end

  it "/ja/browse?page=2 からの「前へ」も /browse のままパラメータを保持する" do
    get "http://#{@domain}/ja/browse?q=piano&page=2"

    expect(response.status).to eq(200)

    doc = Nokogiri::HTML(response.body)
    prev_link = doc.at_css('a[rel="prev"]')
    expect(prev_link).not_to be_nil
    expect(prev_link["href"]).to start_with("/ja/browse?")
    expect(prev_link["href"]).to include("q=piano")
    expect(prev_link["href"]).to include("page=1")
    expect(prev_link["href"]).not_to include("locale=")
  end

  it "トップページのページ送りは従来どおりトップのまま" do
    get "http://#{@domain}/ja/?q=piano"

    expect(response.status).to eq(200)

    doc = Nokogiri::HTML(response.body)
    next_link = doc.at_css('a[rel="next"]')
    expect(next_link).not_to be_nil
    # デフォルトロケール表記（/ja と /ja/ のどちらでも可）のトップのまま
    expect(next_link["href"]).to match(%r{\A/ja/?\?})
    expect(next_link["href"]).to include("q=piano")
    expect(next_link["href"]).to include("page=2")

    url = pageless_url
    expect(url).to match(%r{\A/ja/?\?})
    expect(url).to include("q=piano")
    expect(url).not_to include("browse")
  end
end
