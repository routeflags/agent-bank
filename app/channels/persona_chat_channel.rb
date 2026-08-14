# frozen_string_literal: true

# WebSocket channel for real-time AI persona chat.
#
# Clients subscribe with a chat_session_id parameter.
# When a message is received, it is persisted as a ChatMessage
# and dispatched to PersonaExecutorJob for AI processing.
class PersonaChatChannel < ApplicationCable::Channel
  # Subscribe to the stream for this chat session.
  # Verifies that the user owns the session before allowing subscription.
  def subscribed
    chat_session = ChatSession.find_by(id: params[:chat_session_id])

    unless chat_session
      reject
      return
    end

    unless chat_session.person_id == current_user.id
      reject
      return
    end

    stream_from "persona_chat_#{params[:chat_session_id]}"
  end

  def unsubscribed
    stop_all_streams
  end

  # Handle incoming messages from the client.
  # Persists the user message and queues the AI response job.
  def receive(data)
    chat_session = ChatSession.find_by(id: data['chat_session_id'])

    unless chat_session
      Rails.logger.warn("[PersonaChatChannel] Session not found: #{data['chat_session_id']}")
      return
    end

    unless chat_session.person_id == current_user.id
      Rails.logger.warn("[PersonaChatChannel] Unauthorized message attempt by user #{current_user.id}")
      return
    end

    next_seq = chat_session.chat_messages.maximum(:seq)&.next || 1
    message = chat_session.chat_messages.create!(
      content: data['content'],
      sender_type: 'Person',
      sender_id: current_user.id,
      role: 'user',
      seq: next_seq
    )

    # Phase 4: PersonaExecutorJob will call the AI provider API
    # and broadcast the streaming response back through Action Cable.
    PersonaExecutorJob.perform_later(
      chat_session.id,
      message.id,
      data['content']
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[PersonaChatChannel] Failed to create message: #{e.message}")
  end
end
