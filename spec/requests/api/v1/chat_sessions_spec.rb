# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::ChatSessions", type: :request do
  # Devise integration helpers for request specs (sign_in / sign_out)
  include Devise::Test::IntegrationHelpers

  # ── Test data ────────────────────────────────────────────────────────
  let(:community) { FactoryBot.create(:community) }
  let(:person)    { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing)   { FactoryBot.create(:listing, community_id: community.id, author: person) }
  let(:other_listing) { FactoryBot.create(:listing, community_id: community.id, author: other_person) }

  # ── Helpers ──────────────────────────────────────────────────────────
  def sign_in_as(user)
    sign_in(user)
  end

  # =====================================================================
  # GET /api/v1/chat_sessions
  # =====================================================================
  describe "GET /api/v1/chat_sessions" do
    context "認証済みユーザーがセッション一覧を取得" do
      before do
        FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
        FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id, status: "closed")
        sign_in_as(person)
        get "/api/v1/chat_sessions"
      end

      it "returns 200" do
        expect(response).to have_http_status(200)
      end

      it "returns chat sessions" do
        json = JSON.parse(response.body)
        expect(json["chat_sessions"]).to be_present
      end

      it "returns only the authenticated user's sessions" do
        # Create a session for a different user
        FactoryBot.create(:chat_session, person_id: other_person.id, listing_id: other_listing.id)
        get "/api/v1/chat_sessions"

        json = JSON.parse(response.body)
        session_person_ids = json["chat_sessions"].map { |s| s["person_id"] }
        expect(session_person_ids).to all(eq(person.id))
      end

      it "returns session fields" do
        json = JSON.parse(response.body)
        session = json["chat_sessions"].first
        expect(session).to include("id", "person_id", "listing_id", "status",
                                   "started_at", "created_at", "updated_at")
      end
    end

    context "未認証でセッション一覧を取得 (#6)" do
      before { get "/api/v1/chat_sessions" }

      it "returns 401" do
        expect(response).to have_http_status(401)
      end

      it "returns authentication error" do
        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end
  end

  # =====================================================================
  # POST /api/v1/chat_sessions
  # =====================================================================
  describe "POST /api/v1/chat_sessions" do
    context "購入済みユーザーが新規セッションを作成 (#2)" do
      before do
        FactoryBot.create(:user_plan_subscription, person: person, listing: listing, status: "active")
        sign_in_as(person)
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
      end

      it "returns 201" do
        expect(response).to have_http_status(201)
      end

      it "returns the created session" do
        json = JSON.parse(response.body)
        session = json["chat_session"]
        expect(session["person_id"]).to eq(person.id)
        expect(session["listing_id"]).to eq(listing.id)
        expect(session["status"]).to eq("active")
      end

      it "sets billing_model server-side (ignores client input)" do
        json = JSON.parse(response.body)
        expect(json["chat_session"]["billing_model"]).to be_present
        # Should use the subscription's billing_model, not any client-provided value
      end

      it "persists the session in the database" do
        expect(ChatSession.count).to eq(1)
        expect(ChatSession.first.listing_id).to eq(listing.id)
      end
    end

    context "未購入ユーザーがセッションを作成を試みる" do
      before do
        sign_in_as(person)
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
      end

      it "returns 403 Forbidden" do
        expect(response).to have_http_status(403)
      end

      it "returns purchase_required error type" do
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("purchase_required")
      end

      it "returns Japanese error message" do
        json = JSON.parse(response.body)
        expect(json["error"]).to include("購入してください")
      end

      it "does not create a session" do
        expect(ChatSession.count).to eq(0)
      end
    end

    context "既にセッションがある場合は既存セッションを返す" do
      let!(:existing_session) do
        FactoryBot.create(:user_plan_subscription, person: person, listing: listing, status: "active")
        FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id, status: "active")
      end

      before do
        sign_in_as(person)
      end

      it "returns 200 OK (not 201)" do
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
        expect(response).to have_http_status(200)
      end

      it "returns the existing session" do
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
        json = JSON.parse(response.body)
        expect(json["chat_session"]["id"]).to eq(existing_session.id)
      end

      it "does not create a new session" do
        expect {
          post "/api/v1/chat_sessions", params: { listing_id: listing.id }
        }.not_to change(ChatSession, :count)
      end
    end

    context "存在しない listing_id でセッションを作成 (#8)" do
      before do
        sign_in_as(person)
        post "/api/v1/chat_sessions", params: { listing_id: -1 }
      end

      it "returns 404" do
        expect(response).to have_http_status(404)
      end

      it "returns not found error" do
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("ペルソナが見つかりません")
      end
    end

    context "未認証でセッションを作成 (#7)" do
      before do
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
      end

      it "returns 401" do
        expect(response).to have_http_status(401)
      end
    end
  end

  # =====================================================================
  # GET /api/v1/chat_sessions/:id
  # =====================================================================
  describe "GET /api/v1/chat_sessions/:id" do
    context "認証済みユーザーがセッション詳細を取得 (#3)" do
      let!(:session_record) do
        FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
      end

      before do
        # Attach messages to the session
        FactoryBot.create(:chat_message,
               chat_session: session_record,
               sender_type: "Person",
               sender_id: person.id,
               content: "Hello",
               role: "user",
               seq: 1)
        FactoryBot.create(:chat_message,
               chat_session: session_record,
               sender_type: nil,
               sender_id: nil,
               content: "Hi there!",
               role: "assistant",
               seq: 2)

        sign_in_as(person)
        get "/api/v1/chat_sessions/#{session_record.id}"
      end

      it "returns 200" do
        expect(response).to have_http_status(200)
      end

      it "returns session detail with messages" do
        json = JSON.parse(response.body)
        session = json["chat_session"]
        expect(session["id"]).to eq(session_record.id)
        expect(session["messages"]).to be_an(Array)
        expect(session["messages"].length).to eq(2)
      end

      it "returns messages in chronological order" do
        json = JSON.parse(response.body)
        messages = json["chat_session"]["messages"]
        expect(messages.first["role"]).to eq("user")
        expect(messages.first["content"]).to eq("Hello")
        expect(messages.last["role"]).to eq("assistant")
        expect(messages.last["content"]).to eq("Hi there!")
      end

      it "includes message token counts" do
        json = JSON.parse(response.body)
        message = json["chat_session"]["messages"].first
        expect(message).to include("input_tokens", "output_tokens")
      end
    end

    context "他人のセッション詳細を取得 (#9)" do
      let!(:other_session) do
        FactoryBot.create(:chat_session, person_id: other_person.id, listing_id: other_listing.id)
      end

      before do
        sign_in_as(person)
        get "/api/v1/chat_sessions/#{other_session.id}"
      end

      it "returns 404" do
        expect(response).to have_http_status(404)
      end

      it "returns not found error" do
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("見つかりません")
      end
    end
  end

  # =====================================================================
  # PATCH /api/v1/chat_sessions/:id
  # =====================================================================
  describe "PATCH /api/v1/chat_sessions/:id" do
    context "認証済みユーザーがセッションを終了 (#4)" do
      let!(:session_record) do
        FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
      end

      before do
        sign_in_as(person)
        patch "/api/v1/chat_sessions/#{session_record.id}",
              params: { status: "closed" }
      end

      it "returns 200" do
        expect(response).to have_http_status(200)
      end

      it "returns status: closed" do
        json = JSON.parse(response.body)
        expect(json["chat_session"]["status"]).to eq("closed")
      end

      it "sets ended_at timestamp" do
        json = JSON.parse(response.body)
        expect(json["chat_session"]["ended_at"]).to be_present
      end

      it "persists the closed status" do
        session_record.reload
        expect(session_record.status).to eq("closed")
        expect(session_record.ended_at).to be_present
      end
    end

    context "他人のセッションを終了 (#10)" do
      let!(:other_session) do
        FactoryBot.create(:chat_session, person_id: other_person.id, listing_id: other_listing.id)
      end

      before do
        sign_in_as(person)
        patch "/api/v1/chat_sessions/#{other_session.id}",
              params: { status: "closed" }
      end

      it "returns 404" do
        expect(response).to have_http_status(404)
      end

      it "does not modify the session" do
        other_session.reload
        expect(other_session.status).to eq("active")
      end
    end

    context "無効な status パラメータ" do
      let!(:session_record) do
        FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
      end

      before do
        sign_in_as(person)
        patch "/api/v1/chat_sessions/#{session_record.id}",
              params: { status: "invalid_status" }
      end

      it "returns 422" do
        expect(response).to have_http_status(422)
      end

      it "returns error message" do
        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end
  end

  # =====================================================================
  # POST /api/v1/chat_sessions — Purchase verification edge cases
  # =====================================================================
  describe "POST /api/v1/chat_sessions — 購入検証エッジケース" do
    context "サブスクリプションが期限切れの場合" do
      before do
        FactoryBot.create(:user_plan_subscription, person: person, listing: listing,
          status: "expired", current_period_end: 1.day.ago)
        sign_in_as(person)
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
      end

      it "returns 403" do
        expect(response).to have_http_status(403)
      end

      it "does not create a session" do
        expect(ChatSession.count).to eq(0)
      end
    end

    context "サブスクリプションがキャンセル済みの場合" do
      before do
        FactoryBot.create(:user_plan_subscription, person: person, listing: listing,
          status: "cancelled")
        sign_in_as(person)
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
      end

      it "returns 403" do
        expect(response).to have_http_status(403)
      end
    end

    context "複数ペルソナを購入済みの場合" do
      let(:other_listing) { FactoryBot.create(:listing, community_id: community.id, author: other_person) }

      before do
        FactoryBot.create(:user_plan_subscription, person: person, listing: listing, status: "active")
        FactoryBot.create(:user_plan_subscription, person: person, listing: other_listing, status: "active")
        sign_in_as(person)
      end

      it "各ペルソナで独立したセッションを作成できる" do
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
        expect(response).to have_http_status(201)
        first_id = JSON.parse(response.body)["chat_session"]["id"]

        post "/api/v1/chat_sessions", params: { listing_id: other_listing.id }
        expect(response).to have_http_status(201)
        second_id = JSON.parse(response.body)["chat_session"]["id"]

        expect(first_id).not_to eq(second_id)
        expect(ChatSession.count).to eq(2)
      end
    end

    context "billing_model がサーバー側で決定されること" do
      before do
        FactoryBot.create(:user_plan_subscription,
          person: person, listing: listing,
          status: "active", billing_model: "subscription_with_overage")
        sign_in_as(person)
        post "/api/v1/chat_sessions", params: { listing_id: listing.id }
      end

      it "returns the subscription's billing_model" do
        json = JSON.parse(response.body)
        expect(json["chat_session"]["billing_model"]).to eq("subscription_with_overage")
      end
    end
  end

  # =====================================================================
  # SSE テスト（chat_stream_controller 削除済みのため削除）
  # =====================================================================
end
