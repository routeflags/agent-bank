# frozen_string_literal: true

# Upload endpoint for chat message image attachments.
# POST /api/v1/chat_sessions/:chat_session_id/attachments
#
# Auth: the chat session must belong to the authenticated user.
# Returns { id, url } — the client then references the attachment id
# in the Action Cable `receive` payload (metadata.attachment_id).
class API::V1::ChatAttachmentsController < ApplicationController
  include APIAuthenticatable

  api_requires_scope :read

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
end
