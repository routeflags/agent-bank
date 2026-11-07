# frozen_string_literal: true

# REST API controller for managing AI persona chat sessions.
#
# Provides CRUD operations for chat sessions, scoped to the
# authenticated user. Sessions link a Person to a Listing (persona).
#
# Balance gate (Issues #51, #52):
#   The `create` action requires a wallet balance of at least
#   `PersonaExecutorJob::MIN_BALANCE_CENTS`. Every listing is charged
#   against the wallet balance — no exceptions.
#   There is no per-listing purchase entitlement.
#   The billing_model is determined server-side — client-provided values are ignored.
class API::V1::ChatSessionsController < ApplicationController
  include APIAuthenticatable

  # セッションの参照・作成は読み取り範囲。実行（課金を伴う推論）は別
  # エンドポイント（#144）で run を要求する。
  api_requires_scope :read

  # GET /api/v1/chat_sessions
  def index
    sessions = ChatSession
      .where(person_id: current_user.id)
      .includes(:listing)
      .order(updated_at: :desc)

    # The chat sidebar is per-persona: only list sessions for this listing.
    sessions = sessions.where(listing_id: params[:listing_id]) if params[:listing_id].present?

    render json: {
      chat_sessions: sessions.map { |s| serialize_session(s) }
    }
  end

  # GET /api/v1/chat_sessions/:id
  def show
    session = ChatSession.find(params[:id])

    unless session.person_id == current_user.id
      return render json: { error: "見つかりません" }, status: :not_found
    end

    render json: {
      chat_session: serialize_session(session, include_messages: true)
    }
  end

  # POST /api/v1/chat_sessions
  #
  # Creates a new chat session for the authenticated user and a listing.
  # Requires a sufficient wallet balance (see `purchased?`).
  # If a session already exists for this user+listing pair, returns the existing one.
  def create
    listing = Listing.find_by(id: params[:listing_id])

    unless listing
      return render json: { error: "ペルソナが見つかりません" }, status: :not_found
    end

    # 非公開・削除済みの出品では新規セッションを開始しない（Issue #72）。
    # 既存セッションの継続停止は PersonaChatChannel と PersonaExecutorJob
    # 側で行う。ここでは作成だけを拒否し、課金を発生させない。
    unless listing.chat_available?
      return render json: {
        error: I18n.t("lamprey.chat.listing_closed"),
        error_type: "listing_closed"
      }, status: :forbidden
    end

    # 残高ゲート（Issue #51）。不足時はチャージ導線を出すため、実行時と同じ
    # `insufficient_balance` を返す。
    unless purchased?(current_user, listing)
      return render json: {
        error: "残高が不足しています。チャージしてください",
        error_type: "insufficient_balance",
        current_balance: (current_user.wallet&.balance_cents || 0).to_f
      }, status: :forbidden
    end

    # Return existing ACTIVE session if one already exists (idempotent).
    # Closed sessions must not block creation of a new chat — the "＋ 新規"
    # button closes the current session then requests a fresh one.
    existing_session = ChatSession.find_by(
      person: current_user,
      listing: listing,
      status: "active"
    )

    if existing_session
      return render json: {
        chat_session: serialize_session(existing_session)
      }, status: :ok
    end

    # Server-side billing model determination — never trust client input
    billing_model = ChatSession.billing_model_for(person: current_user, listing: listing)

    session = ChatSession.new(
      person_id: current_user.id,
      listing_id: listing.id,
      billing_model: billing_model,
      started_at: Time.current
    )

    if session.save
      render json: {
        chat_session: serialize_session(session)
      }, status: :created
    else
      render json: { error: session.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/chat_sessions/:id
  def update
    session = ChatSession.find(params[:id])

    unless session.person_id == current_user.id
      return render json: { error: "見つかりません" }, status: :not_found
    end

    if params[:status] == "closed"
      session.close!
      render json: { chat_session: serialize_session(session) }
    elsif params.key?(:title)
      session.update!(title: params[:title].to_s.strip.truncate(100).presence)
      render json: { chat_session: serialize_session(session) }
    else
      render json: { error: "無効な更新です" }, status: :unprocessable_entity
    end
  end

  private

  # Checks whether the person may start a chat for the listing.
  #
  # 課金は残高（ウォレット）一本（Issues #51, #52）。チャットの開始条件は
  # `PersonaExecutorJob` と同じ「残高が最低額以上あること」で、出品ごとの
  # 購入権利（UserPlanSubscription）は見ない。全出品が有料のため例外はない。
  #
  # @param person [Person]
  # @param listing [Listing]
  # @return [Boolean]
  def purchased?(person, listing)
    wallet = person.wallet
    return false if wallet.nil?

    wallet.balance_cents.to_f >= PersonaExecutorJob::MIN_BALANCE_CENTS
  end

  def serialize_session(session, include_messages: false)
    data = {
      id: session.id,
      person_id: session.person_id,
      listing_id: session.listing_id,
      status: session.status,
      billing_model: session.billing_model,
      started_at: session.started_at&.iso8601,
      ended_at: session.ended_at&.iso8601,
      total_tokens: session.total_tokens,
      title: session.title,
      created_at: session.created_at.iso8601,
      updated_at: session.updated_at.iso8601
    }

    if include_messages
      data[:messages] = session.chat_messages.chronological.map { |m|
        attachment = if m.metadata.is_a?(Hash) && m.metadata['attachment_id']
                       session.chat_attachments.find_by(id: m.metadata['attachment_id'])
                     end
        {
          id: m.id,
          sender_type: m.sender_type,
          sender_id: m.sender_id,
          content: m.content,
          role: m.role,
          seq: m.seq,
          input_tokens: m.input_tokens,
          output_tokens: m.output_tokens,
          metadata: m.metadata,
          is_result: m.metadata.is_a?(Hash) && m.metadata["is_result"] == true,
          truncated: m.metadata.is_a?(Hash) && m.metadata["truncated"] == true,
          finish_reason: m.metadata.is_a?(Hash) ? m.metadata["finish_reason"] : nil,
          attachment: attachment && {
            id: attachment.id,
            url: attachment.image.url(:medium)
          },
          created_at: m.created_at.iso8601
        }
      }
    end

    data
  end
end
