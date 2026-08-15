# frozen_string_literal: true

# REST API controller for managing AI persona chat sessions.
#
# Provides CRUD operations for chat sessions, scoped to the
# authenticated user. Sessions link a Person to a Listing (persona).
class API::V1::ChatSessionsController < ApplicationController
  skip_before_action :fetch_community,
                     :fetch_community_plan_expiration_status,
                     :perform_redirect,
                     :initialize_feature_flags,
                     :save_current_host_with_port,
                     :fetch_community_membership,
                     :redirect_removed_locale,
                     :set_locale,
                     :redirect_locale_param,
                     :setup_seo_service,
                     :fetch_community_admin_status,
                     :warn_about_missing_payment_info,
                     :set_homepage_path,
                     :maintenance_warning,
                     :cannot_access_if_banned,
                     :cannot_access_without_confirmation,
                     :ensure_consent_given,
                     :ensure_user_belongs_to_community,
                     :set_display_expiration_notice,
                     :setup_intercom_user,
                     :setup_custom_footer,
                     :disarm_custom_head_script

  before_action :ensure_authenticated

  # GET /api/v1/chat_sessions
  def index
    sessions = ChatSession
      .where(person_id: current_user.id)
      .includes(:listing)
      .order(updated_at: :desc)

    render json: {
      chat_sessions: sessions.map { |s| serialize_session(s) }
    }
  end

  # GET /api/v1/chat_sessions/:id
  def show
    session = ChatSession.find(params[:id])

    unless session.person_id == current_user.id
      return render json: { error: "Not found" }, status: :not_found
    end

    render json: {
      chat_session: serialize_session(session, include_messages: true)
    }
  end

  # POST /api/v1/chat_sessions
  def create
    listing = Listing.find_by(id: params[:listing_id])

    unless listing
      return render json: { error: "Listing not found" }, status: :not_found
    end

    session = ChatSession.new(
      person_id: current_user.id,
      listing_id: listing.id,
      billing_model: params[:billing_model],
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
      return render json: { error: "Not found" }, status: :not_found
    end

    if params[:status] == "closed"
      session.close!
      render json: { chat_session: serialize_session(session) }
    else
      render json: { error: "Invalid status update" }, status: :unprocessable_entity
    end
  end

  private

  def ensure_authenticated
    unless current_user
      render json: { error: "Authentication required" }, status: :unauthorized
    end
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
      created_at: session.created_at.iso8601,
      updated_at: session.updated_at.iso8601
    }

    if include_messages
      data[:messages] = session.chat_messages.chronological.map { |m|
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
          created_at: m.created_at.iso8601
        }
      }
    end

    data
  end
end
