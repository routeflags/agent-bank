# frozen_string_literal: true

# Executes AI persona chat by calling the configured AI provider and
# streaming the response back through Action Cable.
#
# This job is enqueued by PersonaChatChannel when a user sends a message.
# It resolves the AI provider adapter, checks wallet balance, streams
# the AI response, records usage, and deducts cost from the wallet.
#
# Uses Struct-based job pattern consistent with the existing codebase
# (e.g., AutoRechargeCheckJob, ListingCreatedJob).
#
# Flow:
#   1. Resolve adapter via ProviderFactory
#   2. Build messages via ChatCompletionsBuilder
#   3. Check wallet balance (fail fast if insufficient)
#   4. Stream AI response, broadcasting chunks via Action Cable
#   5. Save the complete assistant message to chat_messages
#   6. Create UsageRecord and deduct cost from wallet (atomically)
class PersonaExecutorJob < Struct.new(:chat_session_id, :message_id, :content)

  include DelayedAirbrakeNotification

  # Minimum wallet balance in cents required before making an API call.
  # Prevents making expensive API calls when the user can't afford it.
  MIN_BALANCE_CENTS = 10

  # Required by Delayed::Job when using Struct-based jobs.
  # Sets the community service name for I8n in the job thread.
  def before(job)
    chat_session = ChatSession.find_by(id: chat_session_id)
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(nil) if chat_session
  end

  def perform
    Rails.logger.info(
      "[PersonaExecutorJob] Processing message #{message_id} " \
      "for session #{chat_session_id}: #{content&.truncate(100)}"
    )

    chat_session = ChatSession.includes(listing: { listing_ai_models: :ai_model }).find(chat_session_id)
    listing = chat_session.listing
    person = chat_session.person

    # Step 1: Resolve the AI provider adapter
    adapter = Ai::ProviderFactory.for(listing)

    # Step 2: Build the messages array from session history
    messages = Ai::ChatCompletionsBuilder.new(chat_session).build

    # Step 3: Check wallet balance before making the API call
    wallet = person.wallet
    if wallet.nil?
      broadcast_error("Wallet not found. Please add funds to continue.")
      return
    end

    if wallet.below_threshold?(MIN_BALANCE_CENTS)
      broadcast_error("Insufficient balance. Please top up your wallet to continue.")
      return
    end

    # Step 4: Stream the AI response
    full_content = ""
    usage_result = nil

    adapter.stream(messages) do |chunk|
      full_content += chunk[:content]

      # Broadcast each chunk to connected clients
      ActionCable.server.broadcast(
        "persona_chat_#{chat_session_id}",
        {
          type: "stream_chunk",
          content: chunk[:content]
        }
      )
    end

    # Retrieve usage from the adapter after streaming completes.
    # The adapter stores the last usage result internally.
    usage_result = adapter.last_usage

    # Step 5: Save the complete assistant message
    next_seq = chat_session.chat_messages.maximum(:seq)&.next || 1
    assistant_message = chat_session.chat_messages.create!(
      content: full_content,
      role: "assistant",
      seq: next_seq,
      input_tokens: usage_result.input_tokens,
      output_tokens: usage_result.output_tokens
    )

    # Step 6: Record usage and deduct cost (with dual commission support)
    usage_record = UsageRecord.create!(
      ai_model: adapter.ai_model,
      input_tokens: usage_result.input_tokens,
      output_tokens: usage_result.output_tokens
    )

    billing_service = BillingService.new(
      person: person,
      usage_record: usage_record,
      listing: listing
    )
    billing_result = billing_service.process!

    Rails.logger.info(
      "[PersonaExecutorJob] Billing: base=#{billing_result[:base_cost_cents]}c " \
      "platform_fee=#{billing_result[:platform_commission_cents]}c " \
      "seller_fee=#{billing_result[:seller_commission_cents]}c " \
      "total=#{billing_result[:total_charge_cents]}c"
    )

    # Step 7: Broadcast completion event
    ActionCable.server.broadcast(
      "persona_chat_#{chat_session_id}",
      {
        type: "stream_done",
        messageId: assistant_message.id,
        seq: assistant_message.seq,
        role: "assistant",
        content: assistant_message.content,
        time: (assistant_message.created_at.to_f * 1000).to_i,
        tokens: {
          input: usage_result.input_tokens,
          output: usage_result.output_tokens
        }
      }
    )

    Rails.logger.info(
      "[PersonaExecutorJob] Completed message #{message_id}. " \
      "Tokens: #{usage_result.input_tokens}in/#{usage_result.output_tokens}out"
    )

  rescue Ai::ProviderFactory::ProviderNotConfiguredError => e
    Rails.logger.error("[PersonaExecutorJob] Provider not configured: #{e.message}")
    broadcast_error("AI provider is not configured for this persona.")

  rescue Ai::OpenAiAdapter::ApiError, Ai::AnthropicAdapter::ApiError => e
    Rails.logger.error("[PersonaExecutorJob] AI API error: #{e.message}")
    broadcast_error("Sorry, an error occurred while processing your request.")

  rescue Wallet::InsufficientBalanceError => e
    Rails.logger.warn("[PersonaExecutorJob] Insufficient balance: #{e.message}")
    broadcast_error("Insufficient balance. Please top up your wallet to continue.")

  rescue StandardError => e
    Rails.logger.error("[PersonaExecutorJob] Unexpected error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    broadcast_error("Sorry, an unexpected error occurred. Please try again later.")
  end

  private

  # Broadcasts an error message to the chat session stream.
  #
  # @param message [String] the error message to display to the user
  def broadcast_error(message)
    ActionCable.server.broadcast(
      "persona_chat_#{chat_session_id}",
      {
        type: "stream_error",
        error: message
      }
    )
  end

  # Records usage and deducts cost from the wallet atomically.
  # Both the UsageRecord creation and the wallet deduction are wrapped
  # in a single database transaction to prevent billing inconsistencies.
  #
  # @param chat_session [ChatSession]
  # @param ai_model [AiModel]
  # @param usage [Ai::OpenAiAdapter::Usage, Ai::AnthropicAdapter::Usage]
  # @param wallet [Wallet, nil] pre-fetched wallet to avoid re-query
  def record_usage_and_deduct!(chat_session:, ai_model:, usage:, wallet: nil)
    cost = ai_model.estimate_cost(usage.input_tokens, usage.output_tokens)

    if cost.nil?
      Rails.logger.warn(
        "[PersonaExecutorJob] No pricing set for model #{ai_model.id}, skipping billing"
      )
      return
    end

    return unless cost.positive?

    cost_cents = (cost * 100).to_i
    total_tokens = usage.input_tokens + usage.output_tokens

    wallet ||= chat_session.person&.wallet
    return unless wallet

    ActiveRecord::Base.transaction do
      UsageRecord.create!(
        ai_model: ai_model,
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens
      )

      wallet.deduct_for_usage!(cost_cents, tokens_used: total_tokens)
    end
  end
end
