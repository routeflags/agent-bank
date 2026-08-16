# frozen_string_literal: true

# Server-Sent Events (SSE) endpoint for streaming chat messages.
#
# Clients connect with a `last_event_id` parameter to receive only
# new messages since their last known event. The connection stays open
# so the server can push new messages in real time via Action Cable.
#
# Response headers are set for proper SSE behavior:
# - Content-Type: text/event-stream
# - Cache-Control: no-cache (prevent proxy caching)
# - X-Accel-Buffering: no (disable nginx buffering)
class API::V1::ChatStreamController < ApplicationController
  include ActionController::Live

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

  # GET /api/v1/chat_sessions/:id/stream
  #
  # Streams chat messages as SSE events. Each event is a JSON payload
  # containing the message data. The stream closes when the client
  # disconnects or the session ends.
  def show
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'

    chat_session = ChatSession.find(params[:id])

    unless chat_session.person_id == current_user.id
      sse_write(event: "error", data: { error: "見つかりません" }.to_json)
      response.stream.close
      return
    end

    # Start streaming from the last event the client received.
    # last_event_id is a Unix timestamp (seconds) from the client.
    since = params[:last_event_id].present? ?
      Time.at(params[:last_event_id].to_i) :
      1.year.ago
    last_seq = 0

    sse_write(event: "connected", data: {
      chat_session_id: chat_session.id,
      status: chat_session.status
    }.to_json)

    loop do
      messages = chat_session.chat_messages
        .where("created_at > ? OR (created_at = ? AND seq > ?)", since, since, last_seq)
        .chronological

      messages.each do |message|
        sse_write(event: "message", data: {
          type: "message",
          messageId: message.id,
          seq: message.seq,
          role: message.role,
          time: (message.created_at.to_f * 1000).to_i,
          content: message.content,
          inputTokens: message.input_tokens,
          outputTokens: message.output_tokens
        }.to_json)

        since = message.created_at
        last_seq = message.seq
      end

      # Check if the session has been closed
      chat_session.reload
      if chat_session.status == "closed"
        sse_write(event: "session_closed", data: {
          chat_session_id: chat_session.id,
          ended_at: chat_session.ended_at&.iso8601
        }.to_json)
        break
      end

      # Polling interval is configurable via environment variable
      # to allow tuning without redeployment.
      sleep ENV.fetch("SSE_POLL_INTERVAL", 1.0).to_f
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client disconnected — clean up silently
  rescue StandardError => e
    Rails.logger.error("[ChatStreamController] Error: #{e.message}")
    sse_write(event: "error", data: { error: e.message }.to_json)
  ensure
    response.stream.close
  end

  private

  def ensure_authenticated
    return if current_user

    response.headers['Content-Type'] = 'text/event-stream'
    sse_write(event: "error", data: { error: "ログインが必要です" }.to_json)
    response.stream.close
    throw :abort
  end

  # Write an SSE-formatted event to the response stream.
  #
  # @param event [String] event type name
  # @param data [String] JSON-encoded data payload
  def sse_write(event:, data:)
    response.stream.write("event: #{event}\ndata: #{data}\n\n")
  end
end
