# frozen_string_literal: true

# Placeholder job for AI persona execution.
#
# Phase 4 will implement the actual AI provider API call,
# streaming response handling, and token usage tracking.
# This skeleton logs the invocation and broadcasts a placeholder
# response via Action Cable so the end-to-end flow can be tested.
#
# Uses Struct-based job pattern consistent with the existing codebase
# (e.g., AutoRechargeCheckJob, ListingCreatedJob).
class PersonaExecutorJob < Struct.new(:chat_session_id, :message_id, :content)

  include DelayedAirbrakeNotification

  # Required by Delayed::Job when using Struct-based jobs.
  # Sets the community service name for I18n in the job thread.
  def before(job)
    chat_session = ChatSession.find_by(id: chat_session_id)
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(nil) if chat_session
  end

  def perform
    Rails.logger.info(
      "[PersonaExecutorJob] Processing message #{message_id} " \
      "for session #{chat_session_id}: #{content&.truncate(100)}"
    )

    chat_session = ChatSession.find(chat_session_id)

    # Placeholder: Create a static assistant response.
    # Phase 4 will replace this with actual AI provider API calls
    # (e.g., OpenAI, Anthropic) and streaming response handling.
    placeholder_response = "This is a placeholder response. " \
      "Phase 4 will implement actual AI persona execution."

    assistant_message = chat_session.chat_messages.create!(
      content: placeholder_response,
      sender_type: "System",
      sender_id: "persona_executor",
      role: "assistant",
      input_tokens: 0,
      output_tokens: 0
    )

    # Broadcast the response to all connected clients on this session.
    ActionCable.server.broadcast(
      "persona_chat_#{chat_session_id}",
      {
        type: "message",
        messageId: assistant_message.id,
        seq: assistant_message.seq,
        role: assistant_message.role,
        content: assistant_message.content,
        time: (assistant_message.created_at.to_f * 1000).to_i
      }
    )
  end
end
