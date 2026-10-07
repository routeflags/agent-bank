# frozen_string_literal: true

# Upload endpoint for chat message image attachments.
# POST /api/v1/chat_sessions/:chat_session_id/attachments
#
# Auth: the chat session must belong to the authenticated user.
# Returns { id, url } — the client then references the attachment id
# in the Action Cable `receive` payload (metadata.attachment_id).
class API::V1::ChatAttachmentsController < ApplicationController
  # Same filter surface as API::V1::ChatSessionsController —
  # API endpoint authenticated via Devise session/cookie.
  skip_before_action :verify_authenticity_token

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

  def create
    chat_session = ChatSession.find_by(id: params[:chat_session_id])

    unless chat_session&.person_id == current_user.id
      return render json: { error: "見つかりません" }, status: :not_found
    end

    attachment = chat_session.chat_attachments.build(person: current_user)
    attachment.image = params[:image]

    if attachment.save
      render json: {
        id: attachment.id,
        url: attachment.image.url(:medium)
      }, status: :created
    else
      render json: { error: attachment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def ensure_authenticated
    render json: { error: "ログインが必要です" }, status: :unauthorized unless current_user
  end
end
