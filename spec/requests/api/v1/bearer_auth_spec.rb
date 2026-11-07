# frozen_string_literal: true

require 'rails_helper'

# MCP クライアント向け Bearer 認証（Issue #142）。
#
# - `Authorization: Bearer <token>` で Cookie なしに /api/v1/* を叩ける
# - ヘッダが無ければ従来どおり Devise セッション（既存 spec が回帰を担保）
RSpec.describe "Bearer トークン認証", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }
  let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 1_000) }

  def issue_token(owner: person, scopes: ["read"], expires_at: nil)
    APIToken.issue!(person: owner, name: "MCP", scopes: scopes, expires_at: expires_at)
  end

  def bearer(raw_token)
    { "Authorization" => "Bearer #{raw_token}" }
  end

  def json
    JSON.parse(response.body)
  end

  # =====================================================================
  # 認証
  # =====================================================================
  describe "Bearer での認証" do
    it "Cookie なしでも 200 で自分のデータを返す" do
      _token, raw_token = issue_token

      get "/api/v1/chat_sessions", headers: bearer(raw_token)

      expect(response).to have_http_status(200)
      expect(json).to have_key("chat_sessions")
    end

    it "トークンの所有者として解決される（他人のトークンは見えない）" do
      token, raw_token = issue_token
      issue_token(owner: other_person)

      get "/api/v1/tokens", headers: bearer(raw_token)

      expect(response).to have_http_status(200)
      expect(json["api_tokens"].map { |t| t["id"] }).to eq([token.id])
    end

    it "HTTP の Token スキームも受け付ける" do
      _token, raw_token = issue_token

      get "/api/v1/chat_sessions", headers: { "Authorization" => "Token #{raw_token}" }

      expect(response).to have_http_status(200)
    end

    it "未登録のトークンは 401 invalid_token" do
      get "/api/v1/chat_sessions", headers: bearer("not-a-real-token")

      expect(response).to have_http_status(401)
      expect(json["error"]).to eq("invalid_token")
    end

    it "失効済みトークンは 401 invalid_token" do
      token, raw_token = issue_token
      token.revoke!

      get "/api/v1/chat_sessions", headers: bearer(raw_token)

      expect(response).to have_http_status(401)
      expect(json["error"]).to eq("invalid_token")
    end

    it "期限切れトークンは 401 invalid_token" do
      _token, raw_token = issue_token(expires_at: 1.minute.ago)

      get "/api/v1/chat_sessions", headers: bearer(raw_token)

      expect(response).to have_http_status(401)
      expect(json["error"]).to eq("invalid_token")
    end

    it "Bearer も Cookie も無ければ従来どおり 401" do
      get "/api/v1/chat_sessions"

      expect(response).to have_http_status(401)
      expect(json["error"]).to eq("ログインが必要です")
    end

    it "Cookie 認証は Bearer が無ければ従来どおり動く" do
      sign_in(person)

      get "/api/v1/chat_sessions"

      expect(response).to have_http_status(200)
    end

    it "Bearer と Cookie が同居したら Bearer を優先する（無効なら Cookie に落ちない）" do
      sign_in(person)

      get "/api/v1/chat_sessions", headers: bearer("not-a-real-token")

      expect(response).to have_http_status(401)
      expect(json["error"]).to eq("invalid_token")
    end

    it "Bearer でトークンを発行できる（Cookie なし）" do
      _token, raw_token = issue_token

      post "/api/v1/tokens", params: { name: "2 つ目" }, headers: bearer(raw_token)

      expect(response).to have_http_status(201)
      expect(json["raw_token"]).to be_present
      expect(person.api_tokens.count).to eq(2)
    end
  end

  # =====================================================================
  # scope
  # =====================================================================
  describe "scope の適用" do
    it "read のトークンで tokens を参照できる" do
      _token, raw_token = issue_token(scopes: ["read"])

      get "/api/v1/tokens", headers: bearer(raw_token)

      expect(response).to have_http_status(200)
    end

    it "run のトークンは read を包含する" do
      _token, raw_token = issue_token(scopes: ["run"])

      get "/api/v1/tokens", headers: bearer(raw_token)

      expect(response).to have_http_status(200)
    end

    context "run を要求するエンドポイント（#144 で追加予定）の場合" do
      # `api_requires_scope` の仕組みを検証するため、tokens コントローラの
      # 必要 scope を一時的に run に差し替える。
      around do |example|
        original = API::V1::TokensController.api_required_scope
        API::V1::TokensController.api_requires_scope :run
        example.run
      ensure
        API::V1::TokensController.api_required_scope = original
      end

      it "read だけのトークンは 403 insufficient_scope" do
        _token, raw_token = issue_token(scopes: ["read"])

        get "/api/v1/tokens", headers: bearer(raw_token)

        expect(response).to have_http_status(403)
        expect(json["error"]).to eq("insufficient_scope")
      end

      it "run のトークンは通る" do
        _token, raw_token = issue_token(scopes: ["run"])

        get "/api/v1/tokens", headers: bearer(raw_token)

        expect(response).to have_http_status(200)
      end

      it "Cookie 認証には scope の概念が無いので通る" do
        sign_in(person)

        get "/api/v1/tokens"

        expect(response).to have_http_status(200)
      end
    end
  end

  # =====================================================================
  # last_used_at
  # =====================================================================
  describe "last_used_at の記録" do
    it "初回の認証で記録される" do
      token, raw_token = issue_token
      expect(token.last_used_at).to be_nil

      get "/api/v1/chat_sessions", headers: bearer(raw_token)

      expect(token.reload.last_used_at).to be_present
    end

    it "1 分以内の連続アクセスでは更新しない（updated_at も動かさない）" do
      token, raw_token = issue_token
      get "/api/v1/chat_sessions", headers: bearer(raw_token)
      token.reload
      recorded_at = token.last_used_at
      updated_at = token.updated_at

      get "/api/v1/chat_sessions", headers: bearer(raw_token)

      token.reload
      expect(token.last_used_at).to eq(recorded_at)
      expect(token.updated_at).to eq(updated_at)
    end

    it "1 分以上経っていれば更新する" do
      token, raw_token = issue_token
      stale = 2.minutes.ago
      token.update_columns(last_used_at: stale)

      get "/api/v1/chat_sessions", headers: bearer(raw_token)

      expect(token.reload.last_used_at).to be > stale
    end
  end
end
