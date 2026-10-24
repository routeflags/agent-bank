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
    Rails.logger.info("[PersonaChatChannel] receive session=#{data['chat_session_id']} user=#{current_user&.id}")
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
    metadata = {}
    attachment_id = data['attachment_id'].presence
    if attachment_id
      attachment = chat_session.chat_attachments.find_by(id: attachment_id, person_id: current_user.id)
      metadata['attachment_id'] = attachment.id if attachment
    end

    # Execution settings from the client (token limit, output length, tone).
    # Whitelisted — never trust raw client input beyond these keys.
    settings = data['settings']
    if settings.is_a?(Hash)
      metadata['settings'] = {
        'token_limit' => settings['token_limit'].to_i.clamp(100, 32_000),
        'output_length' => %w[short standard long].include?(settings['output_length']) ? settings['output_length'] : 'standard',
        'tone' => %w[polite casual professional friendly].include?(settings['tone']) ? settings['tone'] : 'polite'
      }
    end

    message = chat_session.chat_messages.create!(
      content: data['content'],
      sender_type: 'Person',
      sender_id: current_user.id,
      role: 'user',
      seq: next_seq,
      metadata: metadata.presence
    )

    # Auto-title: name the session after its first user message so the
    # history sidebar shows meaningful labels instead of a constant.
    if chat_session.title.blank? && data['content'].present?
      chat_session.update!(title: data['content'].to_s.strip.truncate(30))
    end

    # Phase 4: PersonaExecutorJob will call the AI provider API
    # and broadcast the streaming response back through Action Cable.
    # Use Delayed::Job.enqueue (Struct-based job pattern) — the job class
    # is not an ActiveJob and does not respond to perform_later.
    Delayed::Job.enqueue(
      PersonaExecutorJob.new(chat_session.id, message.id, data['content']),
      priority: 0
    )
    Rails.logger.info("[PersonaChatChannel] enqueued session=#{chat_session.id} message=#{message.id}")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[PersonaChatChannel] Failed to create message: #{e.message}")
  end
end
