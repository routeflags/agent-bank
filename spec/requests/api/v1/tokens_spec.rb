# frozen_string_literal: true

require 'rails_helper'

# MCP 用パーソナルアクセストークン API（Issue #141）。
# 認証は当面 Devise セッション（sign_in）。Bearer 認証は #142。
RSpec.describe "Api::V1::Tokens", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }

  def issue_token(owner: person, scopes: ["read"], name: "テスト用")
    APIToken.issue!(person: owner, name: name, scopes: scopes)
  end

  def json
    JSON.parse(response.body)
  end

  # =====================================================================
  # POST /api/v1/tokens
  # =====================================================================
  describe "POST /api/v1/tokens" do
    before { sign_in(person) }

    it "平文トークンを一度だけ返す" do
      post "/api/v1/tokens", params: { name: "Claude Desktop", scopes: ["read", "run"] }

      expect(response).to have_http_status(201)
      expect(json["raw_token"]).to be_present
      expect(json["api_token"]).to include(
        "name" => "Claude Desktop",
        "scopes" => ["read", "run"],
        "daily_cost_limit_cents" => 500
      )
    end

    it "DB には digest だけを残す" do
      post "/api/v1/tokens", params: { name: "Claude Desktop", scopes: ["read"] }

      raw_token = json["raw_token"]
      token = person.api_tokens.reload.last

      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))
      expect(APIToken.find_by(token_digest: raw_token)).to be_nil
    end

    it "レスポンスに digest を含めない" do
      post "/api/v1/tokens", params: { name: "Claude Desktop" }

      expect(json["api_token"]).not_to have_key("token_digest")
      expect(response.body).not_to include("token_digest")
    end

    it "scopes を省略すると read だけが付く" do
      post "/api/v1/tokens", params: { name: "Claude Desktop" }

      expect(response).to have_http_status(201)
      expect(json["api_token"]["scopes"]).to eq(["read"])
    end

    it "不明なスコープは 422" do
      post "/api/v1/tokens", params: { name: "Claude Desktop", scopes: ["admin"] }

      expect(response).to have_http_status(422)
      expect(json["error"]).to be_present
      expect(person.api_tokens.count).to eq(0)
    end

    it "名前が空なら 422" do
      post "/api/v1/tokens", params: { name: "" }

      expect(response).to have_http_status(422)
      expect(person.api_tokens.count).to eq(0)
    end

    it "未認証なら 401" do
      sign_out(person)
      post "/api/v1/tokens", params: { name: "Claude Desktop" }

      expect(response).to have_http_status(401)
      expect(APIToken.count).to eq(0)
    end
  end

  # =====================================================================
  # GET /api/v1/tokens
  # =====================================================================
  describe "GET /api/v1/tokens" do
    let!(:own_token) { issue_token(name: "自分のトークン").first }
    let!(:others_token) { issue_token(owner: other_person, name: "他人のトークン").first }

    before { sign_in(person) }

    it "本人のトークンだけを返す" do
      get "/api/v1/tokens"

      expect(response).to have_http_status(200)
      names = json["api_tokens"].map { |t| t["name"] }
      expect(names).to eq(["自分のトークン"])
    end

    it "平文も digest も返さない" do
      get "/api/v1/tokens"

      expect(json["api_tokens"].first).not_to include("token_digest", "raw_token")
      expect(response.body).not_to include(own_token.token_digest)
    end

    it "失効済みトークンも一覧には出す（revoked_at で判別）" do
      own_token.revoke!
      get "/api/v1/tokens"

      expect(json["api_tokens"].first["revoked_at"]).to be_present
    end

    it "未認証なら 401" do
      sign_out(person)
      get "/api/v1/tokens"

      expect(response).to have_http_status(401)
    end
  end

  # =====================================================================
  # DELETE /api/v1/tokens/:id
  # =====================================================================
  describe "DELETE /api/v1/tokens/:id" do
    before { sign_in(person) }

    it "自分のトークンを失効させる" do
      token, raw_token = issue_token

      delete "/api/v1/tokens/#{token.id}"

      expect(response).to have_http_status(200)
      expect(json["api_token"]["revoked_at"]).to be_present
      expect(token.reload.revoked?).to be true
      expect(APIToken.authenticate(raw_token)).to be_nil
    end

    it "他人のトークンは失効できない（404）" do
      others_token, raw_token = issue_token(owner: other_person)

      delete "/api/v1/tokens/#{others_token.id}"

      expect(response).to have_http_status(404)
      expect(others_token.reload.revoked?).to be false
      expect(APIToken.authenticate(raw_token)).to eq(others_token)
    end

    it "存在しない id は 404" do
      delete "/api/v1/tokens/0"

      expect(response).to have_http_status(404)
    end

    it "未認証なら 401" do
      token, = issue_token
      sign_out(person)

      delete "/api/v1/tokens/#{token.id}"

      expect(response).to have_http_status(401)
      expect(token.reload.revoked?).to be false
    end
  end
end
