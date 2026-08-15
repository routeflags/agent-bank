# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::ChatSessions", type: :request do
  # Devise integration helpers for request specs (sign_in / sign_out)
  include Devise::Test::IntegrationHelpers

  # ── Test data ────────────────────────────────────────────────────────
  let(:community) { create(:community) }
  let(:person)    { create(:person, community_id: community.id) }
  let(:other_person) { create(:person, community_id: community.id) }
  let(:listing)   { create(:listing, community_id: community.id, author: person) }
  let(:other_listing) { create(:listing, community_id: community.id, author: other_person) }

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
        create(:chat_session, person_id: person.id, listing_id: listing.id)
        create(:chat_session, person_id: person.id, listing_id: listing.id, status: "closed")
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
        create(:chat_session, person_id: other_person.id, listing_id: other_listing.id)
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
    context "認証済みユーザーが新規セッションを作成 (#2)" do
      let(:params) do
        {
          listing_id: listing.id,
          billing_model: "token"
        }
      end

      before do
        sign_in_as(person)
        post "/api/v1/chat_sessions", params: params
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

      it "persists the session in the database" do
        expect(ChatSession.count).to eq(1)
        expect(ChatSession.first.listing_id).to eq(listing.id)
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
        expect(json["error"]).to eq("Listing not found")
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
        create(:chat_session, person_id: person.id, listing_id: listing.id)
      end

      before do
        # Attach messages to the session
        create(:chat_message,
               chat_session: session_record,
               sender_type: "Person",
               sender_id: person.id,
               content: "Hello",
               role: "user",
               seq: 1)
        create(:chat_message,
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
        create(:chat_session, person_id: other_person.id, listing_id: other_listing.id)
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
        expect(json["error"]).to eq("Not found")
      end
    end
  end

  # =====================================================================
  # PATCH /api/v1/chat_sessions/:id
  # =====================================================================
  describe "PATCH /api/v1/chat_sessions/:id" do
    context "認証済みユーザーがセッションを終了 (#4)" do
      let!(:session_record) do
        create(:chat_session, person_id: person.id, listing_id: listing.id)
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
        create(:chat_session, person_id: other_person.id, listing_id: other_listing.id)
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
        create(:chat_session, person_id: person.id, listing_id: listing.id)
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
  # GET /api/v1/chat_sessions/:id/stream (SSE)
  # =====================================================================
  describe "GET /api/v1/chat_sessions/:id/stream" do
    context "SSE ストリーミング接続 — 認証済み (#5)" do
      let!(:session_record) do
        # Use a closed session so the SSE loop terminates immediately
        create(:chat_session,
               person_id: person.id,
               listing_id: listing.id,
               status: "closed",
               ended_at: Time.current)
      end

      before do
        sign_in_as(person)
      end

      it "returns text/event-stream content type" do
        get "/api/v1/chat_sessions/#{session_record.id}/stream"
        expect(response.content_type).to include("text/event-stream")
      end

      it "includes connected event in the stream" do
        get "/api/v1/chat_sessions/#{session_record.id}/stream"
        expect(response.body).to include("event: connected")
      end

      it "includes session_closed event for closed sessions" do
        get "/api/v1/chat_sessions/#{session_record.id}/stream"
        expect(response.body).to include("event: session_closed")
      end

      it "includes chat_session_id in connected event data" do
        get "/api/v1/chat_sessions/#{session_record.id}/stream"
        expect(response.body).to include("chat_session_id")
      end
    end

    context "SSE で未認証接続 (#11)" do
      let!(:session_record) do
        create(:chat_session, person_id: person.id, listing_id: listing.id)
      end

      it "returns error event" do
        get "/api/v1/chat_sessions/#{session_record.id}/stream"
        expect(response.body).to include("event: error")
        expect(response.body).to include("Authentication required")
      end
    end

    context "他人のセッションに SSE 接続" do
      let!(:other_session) do
        create(:chat_session,
               person_id: other_person.id,
               listing_id: other_listing.id,
               status: "closed",
               ended_at: Time.current)
      end

      before { sign_in_as(person) }

      it "returns error event for unauthorized session" do
        get "/api/v1/chat_sessions/#{other_session.id}/stream"
        expect(response.body).to include("event: error")
        expect(response.body).to include("Not found")
      end
    end
  end
end
