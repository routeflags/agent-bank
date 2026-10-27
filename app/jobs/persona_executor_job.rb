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
#   4. Stream the AI response, broadcasting chunks via Action Cable
#   5. Save the complete assistant message to chat_messages, recording
#      a token-cap cutoff (finish_reason length/max_tokens) in metadata
#   6. Create UsageRecord and deduct cost from wallet (atomically)
class PersonaExecutorJob < Struct.new(:chat_session_id, :message_id, :content)

  include DelayedAirbrakeNotification

  # Minimum wallet balance in cents required before making an API call.
  # Prevents making expensive API calls when the user can't afford it.
  MIN_BALANCE_CENTS = 10

  # Finish reasons that mean the response was cut off by the output token cap.
  # OpenAI reports "length"; Anthropic reports "max_tokens".
  # Any other reason ("stop" / "end_turn" / nil) is a normal completion.
  TRUNCATED_FINISH_REASONS = %w[length max_tokens].freeze

  # Provider error codes that keep failing until an operator fixes billing
  # or spend limits. Retrying or asking the user to resend cannot help.
  PROVIDER_BILLING_ERROR_CODES = %w[
    credit_balance_exhausted
    insufficient_quota
    quota_exceeded
    billing_hard_limit_reached
    billing_not_active
    organization_spend_limit_exceeded
    project_spend_limit_exceeded
  ].freeze

  # HTTP statuses that mean the provider rejected our credentials.
  PROVIDER_AUTH_ERROR_STATUSES = [401, 403].freeze

  # Required by Delayed::Job when using Struct-based jobs.
  # Sets the community service name for I8n in the job thread.
  def before(job)
    chat_session = ChatSession.find_by(id: chat_session_id)
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(nil) if chat_session
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- pre-existing long method
  # (109 lines before this change) plus one multiline rescue; refactoring the
  # streaming/billing flow is out of scope.
  def perform
    Rails.logger.info(
      "[PersonaExecutorJob] Processing message #{message_id} " \
      "for session #{chat_session_id}: #{content&.truncate(100)}"
    )

    chat_session = ChatSession.includes(listing: { listing_ai_models: :ai_model }).find(chat_session_id)
    listing = chat_session.listing
    person = chat_session.person

    # 非公開・削除済みの出品では外部 API を呼ばず課金もしない（Issue #72）。
    # チャンネル側の拒否をすり抜けた送信（投入済みジョブ等）の最終防衛線。
    unless listing&.chat_available?
      broadcast_error(
        I18n.t("lamprey.chat.listing_closed"),
        error_type: "listing_closed"
      )
      return
    end

    # Step 1: Resolve the AI provider adapter
    adapter = Ai::ProviderFactory.for(listing)

    # Read execution settings (token limit, output length, tone) saved on
    # the triggering user message by PersonaChatChannel.
    settings = extract_settings(chat_session)

    # Step 2: Build the messages array from session history
    messages = Ai::ChatCompletionsBuilder.new(chat_session, settings).build

    # Resolve the output token cap: client override clamped to sane bounds.
    max_tokens = settings.is_a?(Hash) && settings["token_limit"].to_i.positive? ? settings["token_limit"].to_i : nil

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
    finish_reason = nil
    usage_result = nil

    adapter.stream(messages, max_tokens: max_tokens) do |chunk|
      # The terminal chunk may carry only the finish reason (no content),
      # so record the reason even when there is nothing to append.
      chunk_reason = chunk[:finish_reason] || chunk[:stop_reason]
      finish_reason ||= chunk_reason if chunk_reason.present?

      full_content += chunk[:content].to_s

      # Broadcast each chunk to connected clients
      ActionCable.server.broadcast(
        "persona_chat_#{chat_session_id}",
        {
          type: "stream_chunk",
          content: chunk[:content]
        }
      )
    end

    # Fall back to the adapter's recorded reason: it survives terminal
    # chunks that carry no content and are never yielded.
    if finish_reason.nil? && adapter.respond_to?(:last_finish_reason)
      finish_reason = adapter.last_finish_reason
    end
    truncated = TRUNCATED_FINISH_REASONS.include?(finish_reason)

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
    is_result = Ai::ResultDetector.result?(full_content)

    # Record a token-cap cutoff in metadata so a truncated reply stays
    # identifiable after reload. Normal completions store nothing extra.
    assistant_metadata = nil
    if is_result || truncated
      assistant_metadata = {}
      assistant_metadata["is_result"] = true if is_result
      if truncated
        assistant_metadata["truncated"] = true
        assistant_metadata["finish_reason"] = finish_reason
      end
    end

    ActiveRecord::Base.transaction do
      next_seq = chat_session.chat_messages.maximum(:seq)&.next || 1
      assistant_message = chat_session.chat_messages.create!(
        content: full_content,
        role: "assistant",
        seq: next_seq,
        input_tokens: usage_result.input_tokens,
        output_tokens: usage_result.output_tokens,
        metadata: assistant_metadata
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
      "seller_payout=#{billing_result[:seller_payout_cents]}c " \
      "total=#{billing_result[:total_charge_cents]}c"
    )

    # Step 7: Broadcast completion event
    # Issue #82: 課金後の残高を返し、フロントの表示を更新する。
    # ウォレットが無い/取得できない場合は nil（フロントは無視する）。
    current_balance = begin
      person.wallet.reload.balance_cents
    rescue StandardError
      nil
    end

    ActionCable.server.broadcast(
      "persona_chat_#{chat_session_id}",
      {
        type: "stream_done",
        messageId: assistant_message.id,
        seq: assistant_message.seq,
        role: "assistant",
        content: assistant_message.content,
        is_result: is_result,
        finish_reason: finish_reason,
        truncated: truncated,
        time: (assistant_message.created_at.to_f * 1000).to_i,
        tokens: {
          input: usage_result.input_tokens,
          output: usage_result.output_tokens
        },
        current_balance: current_balance
      }
    )

    Rails.logger.info(
      "[PersonaExecutorJob] Completed message #{message_id}. " \
      "Tokens: #{usage_result.input_tokens}in/#{usage_result.output_tokens}out " \
      "finish_reason=#{finish_reason.inspect} truncated=#{truncated}"
    )
  rescue Ai::ProviderFactory::ProviderNotConfiguredError => e
    Rails.logger.error("[PersonaExecutorJob] Provider not configured: #{e.message}")
    broadcast_error("このペルソナのAIプロバイダーが設定されていません。")
  rescue Ai::ProviderError => e
    Rails.logger.error(
      "[PersonaExecutorJob] AI provider error status=#{e.status.inspect} " \
      "code=#{e.code.inspect}: #{e.message}"
    )
    broadcast_error(
      provider_error_message(e),
      error_type: provider_error_type(e)
    )
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
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

  # Extracts execution settings (token limit, output length, tone) saved on
  # the triggering user message by PersonaChatChannel.
  #
  # @param chat_session [ChatSession]
  # @return [Hash, nil] the whitelisted settings hash, or nil
  def extract_settings(chat_session)
    user_message = chat_session.chat_messages.find_by(id: message_id)
    return nil unless user_message&.metadata.is_a?(Hash)

    user_message.metadata["settings"]
  end

  # Broadcasts an error message to the chat session stream.
  #
  # The message is also stored as a system message: errors used to live only
  # on the websocket, so after a reload the history showed an unanswered user
  # message with no explanation of what went wrong.
  #
  # @param message [String] the error message to display to the user
  # @param error_type [String, nil] optional error type code (e.g. "insufficient_balance")
  # @param current_balance [Integer, nil] optional current wallet balance in cents
  def broadcast_error(message, error_type: nil, current_balance: nil)
    store_error_message(message, error_type)

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

  # Stores the error as a system message so it survives a page reload.
  # ChatCompletionsBuilder only sends user/assistant messages to the model,
  # so this never leaks into the AI context.
  #
  # @param message [String] the message text the user saw
  # @param error_type [String, nil] optional error type code
  def store_error_message(message, error_type)
    session = ChatSession.find_by(id: chat_session_id)
    return unless session

    metadata = { "is_error" => true }
    metadata["error_type"] = error_type if error_type

    session.chat_messages.create!(
      role: "system",
      content: message,
      seq: session.chat_messages.maximum(:seq)&.next || 1,
      metadata: metadata
    )
  rescue StandardError => e
    # Never let bookkeeping hide the original failure from the user.
    Rails.logger.warn(
      "[PersonaExecutorJob] Failed to store error message for session " \
      "#{chat_session_id}: #{e.message}"
    )
  end

  # Chooses the message shown to the user for a provider failure.
  #
  # End users cannot act on an exhausted API balance or a credential
  # problem, so those point at the operator; only unknown failures keep the
  # generic "try again" text.
  #
  # @param error [Ai::ProviderError]
  # @return [String]
  def provider_error_message(error)
    if PROVIDER_BILLING_ERROR_CODES.include?(error.code)
      "AIの利用枠が不足しているため応答できません。運営にお問い合わせください。"
    elsif PROVIDER_AUTH_ERROR_STATUSES.include?(error.status)
      "AIの接続設定に問題があるため応答できません。運営にお問い合わせください。"
    else
      "リクエストの処理中にエラーが発生しました。もう一度お試しください。"
    end
  end

  # @param error [Ai::ProviderError]
  # @return [String, nil] "provider_billing_error"/"provider_auth_error",
  #   or nil for transient failures
  def provider_error_type(error)
    if PROVIDER_BILLING_ERROR_CODES.include?(error.code)
      "provider_billing_error"
    elsif PROVIDER_AUTH_ERROR_STATUSES.include?(error.status)
      "provider_auth_error"
    end
  end

end
