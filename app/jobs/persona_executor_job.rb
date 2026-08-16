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
      broadcast_error("ウォレットが見つかりません。先にウォレットを追加してください。")
      return
    end

    if wallet.below_threshold?(MIN_BALANCE_CENTS)
      broadcast_error(
        "残高が不足しています。ウォレットにチャージしてください。",
        error_type: "insufficient_balance",
        current_balance: wallet.balance_cents
      )
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

    if usage_result.nil?
      Rails.logger.error("[PersonaExecutorJob] adapter.last_usage returned nil for session #{chat_session_id}")
      broadcast_error("使用量データを取得できませんでした。もう一度お試しください。")
      return
    end

    # Step 5: Save message, record usage, and process billing atomically.
    # Wrapping in a transaction prevents inconsistencies where a UsageRecord
    # exists but no billing occurred (e.g. Wallet::InsufficientBalanceError).
    subscription = UserPlanSubscription.find_by(
      person: person,
      listing: listing,
      status: "active"
    )

    assistant_message = nil
    billing_result = nil

    ActiveRecord::Base.transaction do
      next_seq = chat_session.chat_messages.maximum(:seq)&.next || 1
      assistant_message = chat_session.chat_messages.create!(
        content: full_content,
        role: "assistant",
        seq: next_seq,
        input_tokens: usage_result.input_tokens,
        output_tokens: usage_result.output_tokens
      )

      usage_record = UsageRecord.create!(
        ai_model: adapter.ai_model,
        input_tokens: usage_result.input_tokens,
        output_tokens: usage_result.output_tokens
      )

      billing_service = BillingService.new(
        person: person,
        subscription: subscription,
        usage_record: usage_record,
        listing: listing
      )
      billing_result = billing_service.process!
    end

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
    broadcast_error("このペルソナのAIプロバイダーが設定されていません。")

  rescue Ai::OpenAiAdapter::ApiError, Ai::AnthropicAdapter::ApiError => e
    Rails.logger.error("[PersonaExecutorJob] AI API error: #{e.message}")
    broadcast_error("リクエストの処理中にエラーが発生しました。もう一度お試しください。")

  rescue Wallet::InsufficientBalanceError => e
    Rails.logger.warn("[PersonaExecutorJob] Insufficient balance: #{e.message}")
    broadcast_error(
      "残高が不足しています。ウォレットにチャージしてください。",
      error_type: "insufficient_balance"
    )

  rescue StandardError => e
    Rails.logger.error("[PersonaExecutorJob] Unexpected error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    broadcast_error("予期しないエラーが発生しました。しばらくしてからもう一度お試しください。")
  end

  private

  # Broadcasts an error message to the chat session stream.
  #
  # @param message [String] the error message to display to the user
  # @param error_type [String, nil] optional error type code (e.g. "insufficient_balance")
  # @param current_balance [Integer, nil] optional current wallet balance in cents
  def broadcast_error(message, error_type: nil, current_balance: nil)
    payload = {
      type: "stream_error",
      error: message
    }
    payload[:error_type] = error_type if error_type
    payload[:current_balance] = current_balance if current_balance

    ActionCable.server.broadcast(
      "persona_chat_#{chat_session_id}",
      payload
    )
  end

end
