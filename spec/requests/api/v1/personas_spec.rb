# frozen_string_literal: true

require 'rails_helper'

# ペルソナ検索・取得 API（Issue #145）。
#
# MCP サーバー（#143）の search_personas / get_persona が使う読み取り専用 API。
# 返すのは /browse と同じ公開情報だけで、`skill_markdown`（AI への指示文）の
# 全文は返さない。
RSpec.describe "Api::V1::Personas", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }

  # カテゴリは表示名（翻訳）を持つ。
  let(:default_category) { create_category("スキル") }
  let(:other_category) { create_category("相談") }

  # スキル本文は 200 字よりずっと長くし、末尾と 250 文字目以降に固有の
  # 文字列を置いて、レスポンスに漏れていないことを見る。
  let(:skill_tail) { "SKILL-TAIL-MUST-NOT-LEAK" }
  let(:skill_markdown) { "# スキル\n" + ("あ" * 1_000) + skill_tail }

  def create_category(name)
    category = FactoryBot.create(:category, community: community)
    category.translation_attributes = { en: { name: name } }
    category.save!
    category
  end

  # 検索結果の並びを固定できるよう、並び順に使う時刻（sort_date / created_at）
  # も明示できるようにしている。
  def create_persona(title:, category: nil, description: "説明文", skill_markdown: nil,
                     run_modes: %w[run_online], default_run_mode: "run_online",
                     avg_rating: 0.0, reviews_count: 0,
                     sort_date: 1.day.ago, created_at: 1.day.ago, **attrs)
    listing = FactoryBot.create(
      :listing,
      community_id: community.id,
      author: person,
      category: category || default_category,
      title: title,
      description: description,
      price: Money.new(3_000, "EUR"),
      **attrs
    )
    listing.update_columns(
      skill_markdown: skill_markdown,
      supported_run_modes: run_modes.to_json,
      default_run_mode: default_run_mode,
      avg_rating: avg_rating,
      reviews_count: reviews_count,
      sort_date: sort_date,
      created_at: created_at
    )
    listing
  end

  def json
    JSON.parse(response.body)
  end

  def issue_token(owner: person, scopes: ["read"], expires_at: nil)
    APIToken.issue!(person: owner, name: "MCP", scopes: scopes, expires_at: expires_at)
  end

  def bearer(raw_token)
    { "Authorization" => "Bearer #{raw_token}" }
  end

  # =====================================================================
  # GET /api/v1/personas
  # =====================================================================
  describe "GET /api/v1/personas" do
    describe "認証・認可" do
      it "未ログイン・トークン無しは 401" do
        get "/api/v1/personas"

        expect(response).to have_http_status(401)
        expect(json["error"]).to be_present
      end

      it "未発行のトークンは 401 invalid_token" do
        get "/api/v1/personas", headers: bearer("not-a-real-token")

        expect(response).to have_http_status(401)
        expect(json["error"]).to eq("invalid_token")
      end

      it "失効したトークンは 401 invalid_token" do
        token, raw_token = issue_token
        token.revoke!

        get "/api/v1/personas", headers: bearer(raw_token)

        expect(response).to have_http_status(401)
        expect(json["error"]).to eq("invalid_token")
      end

      it "read スコープの Bearer トークンで参照できる" do
        _token, raw_token = issue_token(scopes: ["read"])
        create_persona(title: "文章校正")

        get "/api/v1/personas", headers: bearer(raw_token)

        expect(response).to have_http_status(200)
        expect(json["personas"].size).to eq(1)
      end
    end

    describe "レスポンス" do
      let!(:persona) do
        create_persona(title: "文章校正", description: "日本語の文章を校正します",
                       category: default_category, avg_rating: 4.5, reviews_count: 3)
      end

      before { sign_in(person) }

      it "公開情報の項目を返す" do
        get "/api/v1/personas"

        expect(response).to have_http_status(200)
        item = json.fetch("personas").first
        expect(item.keys).to match_array(
          %w[id title description price_cents category avg_rating reviews_count run_modes]
        )
        expect(item["id"]).to eq(persona.id)
        expect(item["title"]).to eq("文章校正")
        expect(item["price_cents"]).to eq(3_000)
        expect(item["avg_rating"]).to eq(4.5)
        expect(item["reviews_count"]).to eq(3)
        expect(item["run_modes"]).to eq(["run_online"])
      end

      it "カテゴリは id / url / 表示名を返す（category パラメータにそのまま使える）" do
        get "/api/v1/personas"

        expect(json["personas"].first["category"]).to eq(
          "id" => default_category.id,
          "url" => default_category.url,
          "name" => "スキル"
        )
      end

      it "description は先頭 200 字までに切り詰める" do
        tail = "DESCRIPTION-TAIL-MUST-BE-TRUNCATED"
        create_persona(title: "長い説明", description: ("あ" * 400) + tail)

        get "/api/v1/personas", params: { limit: 50 }

        item = json["personas"].find { |p| p["title"] == "長い説明" }
        expect(item["description"].length).to be <= 200
        expect(item["description"]).to start_with("あああ")
        expect(response.body).not_to include(tail)
      end

      it "skill_markdown は一覧に含めない（全文も抜粋も返さない）" do
        create_persona(title: "スキル付き", skill_markdown: skill_markdown)

        get "/api/v1/personas"

        item = json["personas"].find { |p| p["title"] == "スキル付き" }
        expect(item).not_to have_key("skill_excerpt")
        expect(item).not_to have_key("skill_markdown")
        expect(response.body).not_to include(skill_tail)
        expect(response.body).not_to include("あ" * 250)
      end
    end

    describe "絞り込みと並び順" do
      # sort_date / created_at / avg_rating をずらして並び順を検証する。
      let!(:oldest) do
        create_persona(title: "古い", description: "旧", sort_date: 3.days.ago,
                       created_at: 4.days.ago, avg_rating: 0.0)
      end
      let!(:rated) do
        create_persona(title: "高評価", description: "評", sort_date: 2.days.ago,
                       created_at: 3.days.ago, avg_rating: 4.8)
      end
      let!(:newest) do
        create_persona(title: "新しい", description: "新", sort_date: 1.day.ago,
                       created_at: 1.day.ago, avg_rating: 3.0)
      end

      before { sign_in(person) }

      it "既定は sort_date の降順（ブラウズの既定と同じ）" do
        get "/api/v1/personas"

        expect(json["personas"].map { |p| p["id"] }).to eq([newest.id, rated.id, oldest.id])
      end

      it "sort=newest は作成日時の降順" do
        get "/api/v1/personas", params: { sort: "newest" }

        expect(json["personas"].map { |p| p["id"] }).to eq([newest.id, rated.id, oldest.id])
      end

      it "sort=rating は評価の降順" do
        get "/api/v1/personas", params: { sort: "rating" }

        expect(json["personas"].map { |p| p["id"] }).to eq([rated.id, newest.id, oldest.id])
      end

      it "未知の sort は既定の並びに戻す" do
        get "/api/v1/personas", params: { sort: "unknown" }

        expect(json["personas"].map { |p| p["id"] }).to eq([newest.id, rated.id, oldest.id])
      end

      it "空の query は全件検索として扱う" do
        get "/api/v1/personas", params: { query: "" }

        expect(json["personas"].size).to eq(3)
      end

      it "空白だけの query も全件検索として扱う" do
        get "/api/v1/personas", params: { query: "   " }

        expect(json["personas"].size).to eq(3)
      end

      it "category は url でも id でも絞り込める" do
        create_persona(title: "相談ペルソナ", category: other_category)

        get "/api/v1/personas", params: { category: default_category.url }
        by_url = json["personas"].map { |p| p["id"] }

        get "/api/v1/personas", params: { category: default_category.id }
        by_id = json["personas"].map { |p| p["id"] }

        expect(by_url).to eq([newest.id, rated.id, oldest.id])
        expect(by_id).to eq(by_url)
      end

      it "limit 未指定は既定件数（20）までを返す" do
        get "/api/v1/personas"

        expect(json["personas"].size).to eq(3)
      end

      it "limit=2 で 2 件、page=2 で続きを返す" do
        get "/api/v1/personas", params: { limit: 2 }
        expect(json["personas"].map { |p| p["id"] }).to eq([newest.id, rated.id])

        get "/api/v1/personas", params: { limit: 2, page: 2 }
        expect(json["personas"].map { |p| p["id"] }).to eq([oldest.id])
      end

      it "limit=0 は 1 件（0 件でも 20 件でもない）" do
        get "/api/v1/personas", params: { limit: 0 }

        expect(json["personas"].size).to eq(1)
      end

      it "上限を超える limit でもエラーにならない" do
        get "/api/v1/personas", params: { limit: 500 }

        expect(response).to have_http_status(200)
        expect(json["personas"].size).to eq(3)
      end
    end

    describe "公開範囲" do
      before { sign_in(person) }

      it "非公開・期限切れ・削除済み・未承認の出品は返さない" do
        visible = create_persona(title: "公開中")
        create_persona(title: "非公開", open: false)
        expired = create_persona(title: "期限切れ")
        expired.update_columns(valid_until: 1.day.ago)
        create_persona(title: "削除済み", deleted: true)
        create_persona(title: "未承認", state: "approval_pending")

        get "/api/v1/personas"

        expect(json["personas"].map { |p| p["id"] }).to eq([visible.id])
      end

      it "別のマーケットプレイスの出品は返さない" do
        other_community = FactoryBot.create(:community)
        other_listing = FactoryBot.create(:listing, community_id: other_community.id,
                                                    author: person, title: "別市場")

        get "/api/v1/personas"

        expect(json["personas"].map { |p| p["id"] }).not_to include(other_listing.id)
      end
    end

    describe "N+1" do
      before { sign_in(person) }

      it "カテゴリの取得は件数によらず 1 クエリ" do
        3.times { |i| create_persona(title: "ペルソナ#{i}", category: create_category("カテゴリ#{i}")) }

        queries = []
        subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
          queries << payload[:sql]
        end

        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          get "/api/v1/personas"
        end

        expect(json["personas"].size).to eq(3)
        expect(queries.count { |sql| sql.include?("FROM `categories`") }).to eq(1)
      end
    end
  end

  # =====================================================================
  # GET /api/v1/personas/:id
  # =====================================================================
  describe "GET /api/v1/personas/:id" do
    before { sign_in(person) }

    it "一覧の項目にスキルの抜粋とダウンロード可否を加えて返す" do
      persona = create_persona(
        title: "校正", description: "校正します", avg_rating: 4.2, reviews_count: 5,
        skill_markdown: skill_markdown, run_modes: %w[run_online download],
        default_run_mode: "download"
      )

      get "/api/v1/personas/#{persona.id}"

      expect(response).to have_http_status(200)
      detail = json.fetch("persona")
      expect(detail.keys).to match_array(
        %w[id title description price_cents category avg_rating reviews_count run_modes
           skill_excerpt skill_available_for_download]
      )
      expect(detail["id"]).to eq(persona.id)
      expect(detail["skill_excerpt"].length).to be <= 200
      expect(detail["skill_excerpt"]).to start_with("# スキル")
      expect(detail["skill_available_for_download"]).to be(true)
      expect(detail["run_modes"]).to eq(%w[run_online download])
    end

    it "skill_markdown の全文は返さない" do
      persona = create_persona(title: "校正", skill_markdown: skill_markdown)

      get "/api/v1/personas/#{persona.id}"

      expect(json["persona"]).not_to have_key("skill_markdown")
      expect(response.body).not_to include(skill_tail)
      expect(response.body).not_to include("あ" * 250)
    end

    it "ダウンロード実行を提供していないペルソナは skill_available_for_download=false" do
      persona = create_persona(title: "オンラインのみ", skill_markdown: skill_markdown,
                               run_modes: %w[run_online])

      get "/api/v1/personas/#{persona.id}"

      expect(json["persona"]["skill_available_for_download"]).to be(false)
    end

    it "スキル本文が無ければ skill_available_for_download=false" do
      persona = create_persona(title: "スキル未登録", skill_markdown: nil,
                               run_modes: %w[download], default_run_mode: "download")

      get "/api/v1/personas/#{persona.id}"

      expect(json["persona"]["skill_available_for_download"]).to be(false)
    end

    it "存在しない id は 404" do
      get "/api/v1/personas/0"

      expect(response).to have_http_status(404)
      expect(json["error"]).to be_present
    end

    it "非公開の出品は 404" do
      persona = create_persona(title: "非公開", open: false)

      get "/api/v1/personas/#{persona.id}"

      expect(response).to have_http_status(404)
    end

    it "期限切れの出品は 404" do
      persona = create_persona(title: "期限切れ")
      persona.update_columns(valid_until: 1.day.ago)

      get "/api/v1/personas/#{persona.id}"

      expect(response).to have_http_status(404)
    end

    it "削除済みの出品は 404" do
      persona = create_persona(title: "削除済み", deleted: true)

      get "/api/v1/personas/#{persona.id}"

      expect(response).to have_http_status(404)
    end

    it "別のマーケットプレイスの出品は 404" do
      other_community = FactoryBot.create(:community)
      other_listing = FactoryBot.create(:listing, community_id: other_community.id,
                                                  author: person, title: "別市場")

      get "/api/v1/personas/#{other_listing.id}"

      expect(response).to have_http_status(404)
    end

    it "未ログイン・トークン無しは 401" do
      persona = create_persona(title: "校正")
      sign_out(person)

      get "/api/v1/personas/#{persona.id}"

      expect(response).to have_http_status(401)
    end
  end
end
