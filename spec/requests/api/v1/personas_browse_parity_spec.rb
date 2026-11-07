# frozen_string_literal: true

require 'rails_helper'

# Issue #145: 同じ query / category / sort で、/ja/browse の一覧（listing id の
# 並び）と /api/v1/personas の結果が一致することを固定する。
#
# 実装は「/browse と同じ `search` ハッシュを PersonaSearchQuery が組み立て、
# 同じ ListingIndexService を通す」なので、HTML の商品リンク
# （/ja/listings/<id>-...）を抽出して API の id 列と突き合わせる。
#
# 注意: 検索エンジン（Sphinx）が無い環境では ListingIndexService が
# DatabaseSearchHelper にフォールバックし、そのフォールバックは keywords を
# 見ない（= キーワードでは絞られない）。これはブラウズも同じなので、
# ここで固定するのは「同じパラメタで同じ並びになること」。
RSpec.describe "ペルソナ API と /ja/browse の一致", type: :request do
  let(:domain) { "personas-api-parity.custom.org" }
  let(:community) do
    FactoryBot.create(:community, domain: domain, use_domain: true,
                                  settings: { "locales" => %w[en ja] })
  end
  # マーケットプレイスのメンバー。ホストからコミュニティを解決するミドルウェアが
  # `community_membership` を参照するため、メンバーとして作る。
  let(:person) { FactoryBot.create(:person, member_of: community) }
  # MCP クライアントと同じく Bearer トークンで叩く（Cookie のホスト依存を避ける）。
  let!(:read_token) do
    _token, raw_token = APIToken.issue!(person: person, name: "parity", scopes: ["read"])
    raw_token
  end

  let(:skill_category) { create_category("スキル") }
  let(:consult_category) { create_category("相談") }

  # sort_date / created_at / avg_rating をずらして並び順に差をつける。
  let!(:oldest) do
    create_listing(title: "Parity Oldest", category: skill_category,
                   sort_date: 3.days.ago, created_at: 4.days.ago, avg_rating: 0.0)
  end
  let!(:rated) do
    create_listing(title: "Parity Rated", category: skill_category,
                   sort_date: 2.days.ago, created_at: 3.days.ago, avg_rating: 4.8)
  end
  let!(:newest) do
    create_listing(title: "Parity Newest", category: skill_category,
                   sort_date: 1.day.ago, created_at: 1.day.ago, avg_rating: 3.0)
  end
  let!(:consult) do
    create_listing(title: "Parity Consult", category: consult_category,
                   sort_date: 4.days.ago, created_at: 5.days.ago, avg_rating: 1.0)
  end

  def create_category(name)
    category = FactoryBot.create(:category, community: community)
    category.translation_attributes = { en: { name: name } }
    category.save!
    category
  end

  def create_listing(title:, category:, sort_date:, created_at:, avg_rating:)
    listing = FactoryBot.create(:listing, community_id: community.id, author: person,
                                          category: category, title: title,
                                          description: "#{title} の説明")
    listing.update_columns(sort_date: sort_date, created_at: created_at,
                           avg_rating: avg_rating)
    listing
  end

  # /ja/browse の一覧グリッド（.cards）から listing id を抽出する。
  def browse_listing_ids(params = {})
    get "http://#{domain}/ja/browse", params: params

    expect(response).to have_http_status(200)
    Nokogiri::HTML(response.body)
            .css(".cards article.agent a.agent-art")
            .map { |link| link["href"][%r{/listings/(\d+)-}, 1].to_i }
  end

  def api_listing_ids(params = {})
    get "http://#{domain}/api/v1/personas", params: params,
                                            headers: { "Authorization" => "Bearer #{read_token}" }

    expect(response).to have_http_status(200)
    JSON.parse(response.body).fetch("personas").map { |persona| persona["id"] }
  end

  it "一覧グリッドが抽出できている（比較自体が空になっていない）" do
    ids = browse_listing_ids

    expect(ids).to eq([newest.id, rated.id, oldest.id, consult.id])
  end

  it "既定（query なし・sort なし）で一致する" do
    browse = browse_listing_ids
    expect(browse).not_to be_empty

    expect(api_listing_ids).to eq(browse)
  end

  it "空の query でも一致する（全件検索として扱う）" do
    expect(api_listing_ids(query: "")).to eq(browse_listing_ids(q: ""))
  end

  it "同じ query で一致する" do
    expect(api_listing_ids(query: "Parity")).to eq(browse_listing_ids(q: "Parity"))
  end

  it "category で絞り込んだときも一致する" do
    browse = browse_listing_ids(category: skill_category.url)
    expect(browse).to eq([newest.id, rated.id, oldest.id])

    expect(api_listing_ids(category: skill_category.url)).to eq(browse)
  end

  it "sort=newest でも一致する" do
    browse = browse_listing_ids(sort: "newest")
    expect(browse).to eq([newest.id, rated.id, oldest.id, consult.id])

    expect(api_listing_ids(sort: "newest")).to eq(browse)
  end

  it "sort=rating でも一致する" do
    browse = browse_listing_ids(sort: "rating")
    expect(browse).to eq([rated.id, newest.id, consult.id, oldest.id])

    expect(api_listing_ids(sort: "rating")).to eq(browse)
  end

  it "query と category と sort を同時に指定しても一致する" do
    params = { category: skill_category.url, sort: "rating" }

    expect(api_listing_ids(params.merge(query: "Parity")))
      .to eq(browse_listing_ids(params.merge(q: "Parity")))
  end
end
