# frozen_string_literal: true

require "openssl"

# Receives Freemius server-to-server webhooks.
#
# Freemius acts as the Merchant of Record: after a buyer completes a
# hosted checkout, Freemius notifies this endpoint. The controller verifies the
# request signature (HMAC-SHA256 of the raw body with PRODUCT_SECRET_KEY),
# dispatches by event type, and grants the purchase entitlement or syncs the
# subscription. All handlers are idempotent: repeated delivery of the same
# event must not double-credit.
#
# Real event names (see Issue #43): payment.created / payment.refund /
# subscription.created / subscription.cancelled / subscription.renewal.failed.
# Legacy names (payment.completed etc.) are accepted for backward compatibility
# with existing tests/stubs but are not sent by Freemius.
#
# Reference: https://freemius.com/help/documentation/marketing-automation/events-webhooks/
#   (Validating Webhook Signatures, Types of Events)
#
# Route: POST /webhooks/freemius (see config/routes.rb, next to PayPal IPN)
class FreemiusWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token,
                     :fetch_logged_in_user,
                     :fetch_community,
                     :perform_redirect,
                     :fetch_community_membership,
                     :check_http_auth

  # Supported inbound event types (real names first, legacy aliases after).
  # Real: payment.created (successful payment), payment.refund.
  PAYMENT_CREATED = %w[payment.created payment.completed].freeze
  PAYMENT_REFUND = %w[payment.refund payment.refunded].freeze
  # Checkout metadata type for persona purchases (listing unit).
  # Wallet top-up checkouts carry type: "wallet_topup" (or no type for
  # legacy checkouts); anything other than persona_purchase keeps the
  # existing wallet credit path (dormant for arbitrary-amount top-ups,
  # kept for fixed prepaid plans — see Issue #43).
  PERSONA_PURCHASE = "persona_purchase"
  SUBSCRIPTION_EVENTS = %w[
    subscription.created
    subscription.cancelled
    subscription.renewal.failed
    subscription.renewed
    subscription.expired
  ].freeze

  def receive
    unless valid_signature?
      Rails.logger.warn("[FreemiusWebhook] Invalid signature")
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    event = extract_event_type
    objects = params[:objects] || params["objects"] || {}

    if PAYMENT_CREATED.include?(event)
      handle_payment_completed(objects, event)
    elsif PAYMENT_REFUND.include?(event)
      handle_payment_refunded(objects)
    elsif SUBSCRIPTION_EVENTS.include?(event)
      handle_subscription_event(event, objects)
    else
      Rails.logger.info("[FreemiusWebhook] Ignored event: #{event}")
    end

    render json: { status: "ok" }
  rescue StandardError => e
    Rails.logger.error("[FreemiusWebhook] Error processing #{extract_event_type}: #{e.message}")
    render json: { error: "Internal error" }, status: :internal_server_error
  end

  private

  # Verifies the HMAC signature sent in the x-signature header.
  # The signature covers the raw request body with PRODUCT_SECRET_KEY
  # (legacy FREEMIUS_WEBHOOK_SECRET is accepted for backward compatibility).
  #
  # @return [Boolean]
  def valid_signature?
    secret = FreemiusClient.webhook_secret
    return false if secret.blank?

    signature = request.headers["x-signature"].to_s
    return false if signature.blank?

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  rescue StandardError
    false
  end

  # Extracts the event type from either a string or an object payload.
  # Real Freemius payloads use event.type; legacy tests use a plain string.
  # Rails parses JSON objects into ActionController::Parameters, so both
  # Hash and Parameters shapes are accepted here.
  #
  # @return [String]
  def extract_event_type
    raw = params[:event].nil? ? params["event"] : params[:event]
    if raw.respond_to?(:[]) && !raw.is_a?(String)
      begin
        type = raw[:type] || raw["type"]
      rescue StandardError
        type = nil
      end
      return type.to_s.strip if type.present?

      # Fallback for double-encoded or unexpected shapes: dig manually.
      return raw.to_s.strip
    end
    raw.to_s.strip
  end

  # Dispatches a created payment by its checkout metadata type or plan mapping.
  #   - type: "persona_purchase" (or plan_id → listing mapping) → grants entitlement
  #   - anything else (incl. "wallet_topup" / legacy without type) → credits the wallet
  def handle_payment_completed(objects, event)
    payment = objects[:payment] || objects["payment"] || {}
    payment_id = payment[:id] || payment["id"]
    metadata = payment[:metadata] || payment["metadata"] || {}

    if payment_id.blank?
      Rails.logger.warn("[FreemiusWebhook] #{event} missing payment id: #{objects.inspect[0, 200]}")
      return
    end

    type = metadata[:type] || metadata["type"]
    if type.to_s == PERSONA_PURCHASE || persona_payment?(payment, metadata)
      handle_persona_purchase_completed(payment_id, payment, metadata)
    else
      handle_wallet_topup_completed(payment_id, payment, metadata)
    end
  end

  # Whether the payment corresponds to a persona purchase when no explicit
  # metadata type is present (real Freemius payments carry plan_id, not metadata).
  def persona_payment?(payment, metadata)
    plan_id = payment[:plan_id] || payment["plan_id"] ||
              metadata[:plan_id] || metadata["plan_id"]
    return false if plan_id.to_s.strip.empty?

    FreemiusClient.listing_id_for_plan(plan_id).present?
  end

  # Credits the buyer's wallet for a completed wallet top-up payment.
  # Verifies the payment server-side before crediting: the webhook payload
  # alone is not trusted for amount.
  #
  # Fixed prepaid (Issue #46): `plan_id -> credit (yen)` is resolved solely
  # from `FREEMIUS_TOPUP_PLAN_MAP` (FreemiusTopupPlans). The verified gross
  # (USD cents from Freemius) proves the payment exists; the credited amount
  # is the map value, never the webhook body amount. Legacy payments without
  # plan_id fall back to the verified gross (backward compatibility for
  # existing tests/stubs). Unknown plan_id is skipped (no mis-credit).
  def handle_wallet_topup_completed(payment_id, payment, metadata)
    plan_id = payment[:plan_id] || payment["plan_id"] ||
              metadata[:plan_id] || metadata["plan_id"]
    plan_id = plan_id.to_s.strip.presence

    topup_credit = plan_id ? FreemiusTopupPlans.credit_for_plan(plan_id) : nil
    if plan_id && topup_credit.nil?
      Rails.logger.warn("[FreemiusWebhook] Unknown topup plan_id=#{plan_id.inspect} (payment #{payment_id}), skipping")
      return
    end

    wallet = resolve_wallet_for_topup(payment, metadata)
    if wallet.nil?
      user_id = metadata[:user_id] || metadata["user_id"] ||
                payment[:user_id] || payment["user_id"]
      wallet_id = metadata[:wallet_id] || metadata["wallet_id"]
      Rails.logger.warn("[FreemiusWebhook] payment wallet target not found: user=#{user_id.inspect} wallet=#{wallet_id.inspect} plan=#{plan_id.inspect}, skipping")
      return
    end

    # Server-side verification: fetch the payment from Freemius.
    # Never trust amount from the webhook body.
    verified = verify_payment_completed(payment_id)
    unless verified
      Rails.logger.warn("[FreemiusWebhook] Payment #{payment_id} not verified, skipping")
      return
    end

    credit_cents = topup_credit || verified[:amount_cents]
    if topup_credit
      # Drift check only (warn, never block): hosted page shows the true
      # charge; warn when the verified USD gross diverges from the yen
      # credit converted at the current rate (operational drift signal).
      begin
        converted = FreemiusPricing.configured? ? FreemiusPricing.usd_cents_for_jpy(topup_credit) : nil
        if converted && !FreemiusPricing.within_tolerance?(verified[:amount_cents], converted)
          Rails.logger.warn("[FreemiusWebhook] Topup drift: plan=#{plan_id} verified=#{verified[:amount_cents]}c converted=#{converted}c (credit #{topup_credit} yen)")
        end
      rescue FreemiusPricing::RateMissingError
        nil
      end
    end

    # Idempotent credit with row lock (see Wallet#topup!): concurrent
    # duplicate deliveries credit only once. `freemius:<payment_id>` is
    # matched by exact JSON parse (see Wallet#find_credited_transaction),
    # so `fs_pay_1` never matches `fs_pay_10`. Returns nil if already done.
    credited = wallet.topup!(credit_cents, freemius_payment_id: payment_id)
    if credited.nil?
      Rails.logger.info("[FreemiusWebhook] Duplicate payment #{payment_id}, skipping")
      return
    end

    Rails.logger.info("[FreemiusWebhook] Credited wallet #{wallet.id} #{credit_cents}c (payment #{payment_id} plan #{plan_id.inspect})")
  end

  # Grants the purchase entitlement for a completed persona purchase.
  #
  # サーバー側検証（verify_payment_completed）のあと、購入権利の単一経路である
  # UserPlanSubscriptionService.create_for を呼ぶ。冪等性は二段で担保される:
  #   1. create_for: 同一 person+listing の active 購入権利があれば duplicate として返す
  #      （同じ payment の再送は購入権利・初期トークンを二重に付与しない）
  #   2. Wallet#topup!: payment_reference "freemius:<payment_id>" の厳密一致で
  #      初期トークンの二重チャージ自体を防止
  #
  # listing / person が見つからない場合は警告ログを出してスキップする（500 にしない）。
  # create_for 自体の例外は外側の rescue で 500 になり、Freemius が再送するため
  # 一時的な DB エラーは再試行される（冪等なので二重付与はしない）。
  def handle_persona_purchase_completed(payment_id, payment, metadata)
    listing_id = metadata[:listing_id] || metadata["listing_id"]
    user_id = metadata[:user_id] || metadata["user_id"]
    listing_id ||= listing_id_from_payment(payment, metadata)
    user_id ||= payment[:user_id] || payment["user_id"]

    if listing_id.blank?
      Rails.logger.warn("[FreemiusWebhook] persona_purchase missing listing (plan mapping + metadata): payment=#{payment_id}, skipping")
      return
    end

    listing = Listing.find_by(id: listing_id)
    person = resolve_person(user_id, payment)
    unless listing && person
      Rails.logger.warn("[FreemiusWebhook] persona_purchase target not found: listing=#{listing_id} person=#{user_id.inspect}, skipping")
      return
    end

    # Server-side verification: same as the wallet path — the webhook body
    # alone is not trusted for amount.
    verified = verify_payment_completed(payment_id)
    unless verified
      Rails.logger.warn("[FreemiusWebhook] Payment #{payment_id} not verified, skipping persona purchase")
      return
    end

    result = UserPlanSubscriptionService.create_for(
      person: person,
      listing: listing,
      payment_reference: "freemius:#{payment_id}"
    )

    if result.duplicate?
      Rails.logger.info("[FreemiusWebhook] Duplicate persona purchase payment #{payment_id}, skipping")
    else
      Rails.logger.info("[FreemiusWebhook] Granted persona purchase: listing=#{listing_id} person=#{user_id} (payment #{payment_id})")
    end
  end

  # Fetches the payment from Freemius and verifies its existence/amount.
  # Real Freemius payments have no `status` field (only successful payments
  # exist); legacy stubs use `status: completed/pending`. When a status is
  # present it must be completed-like, otherwise existence + positive amount
  # (gross → cents) is sufficient. Never trust the webhook body amount.
  #
  # @return [Hash, nil] { amount_cents: Integer } when verified, nil otherwise
  def verify_payment_completed(payment_id)
    remote = FreemiusClient.get_payment(payment_id)
    status = remote["status"] || remote[:status]
    if status.present? && !%w[completed complete success successful paid active].include?(status.to_s.downcase)
      Rails.logger.warn("[FreemiusWebhook] Payment #{payment_id} status=#{status.inspect}, not completed")
      return nil
    end

    amount = FreemiusClient.payment_amount_cents(remote)
    return nil unless amount.positive?

    { amount_cents: amount }
  rescue FreemiusClient::ApiError => e
    Rails.logger.error("[FreemiusWebhook] Payment verification failed for #{payment_id}: #{e.message}")
    nil
  end

  # Resolves listing_id from plan mapping when metadata lacks it.
  def listing_id_from_payment(payment, metadata)
    plan_id = payment[:plan_id] || payment["plan_id"] ||
              metadata[:plan_id] || metadata["plan_id"]
    return nil if plan_id.to_s.strip.empty?

    FreemiusClient.listing_id_for_plan(plan_id)
  end

  # Resolves the buyer Person from a local id or Freemius user info.
  # Email matching is exact (downcased): `Person.by_email` uses
  # `WHERE address = ?` on lowercased addresses, so `a@x` never matches
  # `a@xy` or `aa@x` (no prefix confusion like fs_pay_1 vs fs_pay_10).
  def resolve_person(user_id, payment)
    person = Person.find_by(id: user_id) if user_id.present?
    return person if person

    email = webhook_user_email(payment)
    return nil if email.nil?

    Person.by_email(email).first
  rescue StandardError
    nil
  end

  # Resolves the wallet for a top-up: explicit wallet_id → local user_id →
  # exact email match (hosted checkout carries only user_email).
  def resolve_wallet_for_topup(payment, metadata)
    wallet_id = metadata[:wallet_id] || metadata["wallet_id"]
    return Wallet.find_by(id: wallet_id) if wallet_id.present?

    user_id = metadata[:user_id] || metadata["user_id"] ||
              payment[:user_id] || payment["user_id"]
    person = Person.find_by(id: user_id) if user_id.present?
    person ||= begin
      email = webhook_user_email(payment)
      email ? Person.by_email(email).first : nil
    end
    return nil unless person

    person.wallet || person.find_or_create_wallet!(community: person.community)
  rescue StandardError
    nil
  end

  # Extracts the buyer email from the webhook (exact match only).
  # Sources: objects.user.email (Freemius event) → payment.user_email
  # (hosted checkout `user_email` prefill) → payment.user.email.
  # Returns the downcased stripped address (Email addresses are stored
  # lowercased), or nil when absent.
  def webhook_user_email(payment)
    objects_user = params.dig(:objects, :user) || params.dig("objects", "user") || {}
    raw = objects_user[:email] || objects_user["email"] ||
          payment[:user_email] || payment["user_email"]
    if raw.to_s.strip.empty?
      user_obj = payment[:user] || payment["user"]
      if user_obj.respond_to?(:[])
        raw = user_obj[:email] || user_obj["email"]
      end
    end
    email = raw.to_s.strip.downcase
    email.presence
  end

  # Falls back to the person's wallet when wallet_id metadata is absent
  # (real Freemius payments carry user_id, not our wallet_id).
  def wallet_for_user(user_id)
    return nil if user_id.blank?

    person = Person.find_by(id: user_id)
    return nil unless person

    person.wallet || person.find_or_create_wallet!(community: person.community)
  rescue StandardError
    nil
  end

  # Records a refund as a reversing entry and decrements the balance.
  # Delegates to Wallet#refund! which is idempotent and atomic.
  # Lookup is exact (JSON-parsed): LIKE is only a prefilter, so `fs_pay_1`
  # never matches `fs_pay_10`.
  def handle_payment_refunded(objects)
    payment = objects[:payment] || objects["payment"] || {}
    payment_id = payment[:id] || payment["id"]
    return if payment_id.blank?

    original = find_exact_topup_transaction(payment_id)
    unless original
      Rails.logger.warn("[FreemiusWebhook] Refund for unknown payment #{payment_id}")
      return
    end

    wallet = Wallet.find_by(id: original.wallet_id)
    unless wallet
      Rails.logger.warn("[FreemiusWebhook] Wallet not found for refund #{payment_id}")
      return
    end

    refunded = wallet.refund!(freemius_payment_id: payment_id)
    if refunded.nil?
      Rails.logger.info("[FreemiusWebhook] Refund for #{payment_id} already recorded, skipping")
      return
    end

    Rails.logger.info("[FreemiusWebhook] Recorded refund for payment #{payment_id}")
  end

  def sanitize_like(str)
    str.to_s.gsub(/[\\%_]/) { |m| "\\#{m}" }
  end

  # Finds the original top-up transaction for a Freemius payment ID by
  # exact match (JSON-parsed metadata). LIKE is only a prefilter for
  # performance; the final match requires `freemius_payment_id == payment_id`
  # (or legacy `stripe_payment_id` shape with the same value), so prefix
  # confusion (`fs_pay_1` vs `fs_pay_10`) cannot occur.
  def find_exact_topup_transaction(payment_id)
    candidates = CreditTransaction.where(transaction_type: "topup")
                                  .where("metadata LIKE ?", "%\"#{sanitize_like(payment_id)}\"%")
    candidates.find do |tx|
      begin
        meta = JSON.parse(tx.metadata.to_s)
      rescue JSON::ParserError
        next false
      end
      meta["freemius_payment_id"] == payment_id || meta["stripe_payment_id"] == payment_id
    end
  end

  # Syncs subscription lifecycle events to UserPlanSubscription.
  def handle_subscription_event(event, objects)
    subscription = objects[:subscription] || objects["subscription"] || {}
    freemius_id = subscription[:id] || subscription["id"]
    metadata = subscription[:metadata] || subscription["metadata"] || {}
    return if freemius_id.blank?

    record = UserPlanSubscription.find_by(freemius_subscription_id: freemius_id)
    # Fall back to person+listing lookup from metadata for the first event.
    # The state machine reads current_state from the transitions table, so
    # match on current_state rather than the legacy status column.
    if record.nil? && event == "subscription.created"
      person_id = metadata[:person_id] || metadata["person_id"]
      listing_id = metadata[:listing_id] || metadata["listing_id"]
      record = UserPlanSubscription.where(person_id: person_id, listing_id: listing_id)
                                   .detect { |s| s.current_state == "active" }
      record&.update!(freemius_subscription_id: freemius_id)
    end

    case event
    when "subscription.created", "subscription.renewed"
      sync_status(record, "active")
    when "subscription.cancelled"
      sync_status(record, "canceled")
    when "subscription.expired"
      # No "expired" state in the machine; treat as canceled.
      sync_status(record, "canceled")
    when "subscription.renewal.failed"
      sync_status(record, "past_due")
      Rails.logger.warn("[FreemiusWebhook] Renewal failed for subscription #{freemius_id}")
    end

    Rails.logger.info("[FreemiusWebhook] Handled #{event} for #{freemius_id}")
  end

  # Moves the subscription to the target state via the state machine,
  # tolerating records that are already there or cannot transition.
  def sync_status(record, target)
    return if record.nil?
    return if record.current_state == target
    return unless record.can_transition_to?(target.to_sym)

    record.transition_to!(target.to_sym)
  rescue StandardError => e
    Rails.logger.warn("[FreemiusWebhook] Status sync failed: #{e.message}")
  end
end
