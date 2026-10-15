# frozen_string_literal: true

require "openssl"

# Receives Freemius server-to-server webhooks.
#
# Freemius acts as the Merchant of Record: after a buyer completes a
# checkout, Freemius notifies this endpoint. The controller verifies the
# request signature, dispatches by event type, and credits the wallet or
# syncs the subscription. All handlers are idempotent: repeated delivery
# of the same event must not double-credit.
#
# Reference: https://freemius.com/help/documentation/saas-sdk/js-sdk/webhooks/
#
# Route: POST /webhooks/freemius (see config/routes.rb, next to PayPal IPN)
class FreemiusWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token,
                     :fetch_logged_in_user,
                     :fetch_community,
                     :perform_redirect,
                     :fetch_community_membership,
                     :check_http_auth

  # Supported inbound event types.
  PAYMENT_COMPLETED = "payment.completed"
  PAYMENT_REFUNDED = "payment.refunded"
  SUBSCRIPTION_EVENTS = %w[
    subscription.created
    subscription.renewed
    subscription.cancelled
    subscription.expired
    subscription.renewal.failed
  ].freeze

  def receive
    unless valid_signature?
      Rails.logger.warn("[FreemiusWebhook] Invalid signature")
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    event = params[:event].to_s
    objects = params[:objects] || {}

    case event
    when PAYMENT_COMPLETED
      handle_payment_completed(objects)
    when PAYMENT_REFUNDED
      handle_payment_refunded(objects)
    when *SUBSCRIPTION_EVENTS
      handle_subscription_event(event, objects)
    else
      Rails.logger.info("[FreemiusWebhook] Ignored event: #{event}")
    end

    render json: { status: "ok" }
  rescue StandardError => e
    Rails.logger.error("[FreemiusWebhook] Error processing #{params[:event]}: #{e.message}")
    render json: { error: "Internal error" }, status: :internal_server_error
  end

  private

  # Verifies the HMAC signature sent in the x-signature header.
  # The signature covers the raw request body with the webhook secret.
  #
  # @return [Boolean]
  def valid_signature?
    secret = ENV["FREEMIUS_WEBHOOK_SECRET"]
    return false if secret.blank?

    signature = request.headers["x-signature"].to_s
    return false if signature.blank?

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  # Credits the buyer's wallet for a completed payment.
  def handle_payment_completed(objects)
    payment = objects[:payment] || objects["payment"] || {}
    payment_id = payment[:id] || payment["id"]
    metadata = payment[:metadata] || payment["metadata"] || {}
    user_id = metadata[:user_id] || metadata["user_id"]
    wallet_id = metadata[:wallet_id] || metadata["wallet_id"]
    amount = (payment[:amount_cents] || payment["amount_cents"] || payment[:amount] || payment["amount"]).to_i

    if payment_id.blank? || user_id.blank? || wallet_id.blank? || amount <= 0
      Rails.logger.warn("[FreemiusWebhook] payment.completed missing fields: #{objects.inspect[0, 200]}")
      return
    end

    wallet = Wallet.find_by(id: wallet_id)
    unless wallet
      Rails.logger.warn("[FreemiusWebhook] Wallet not found: #{wallet_id}")
      return
    end

    # Idempotency: same Freemius payment must not credit twice.
    already = wallet.credit_transactions.where(transaction_type: "topup")
                    .where("metadata LIKE ?", "%#{payment_id}%").exists?
    if already
      Rails.logger.info("[FreemiusWebhook] Duplicate payment #{payment_id}, skipping")
      return
    end

    wallet.topup!(amount, freemius_payment_id: payment_id)
    Rails.logger.info("[FreemiusWebhook] Credited wallet #{wallet_id} #{amount}c (payment #{payment_id})")
  end

  # Records a refund as a reversing entry.
  def handle_payment_refunded(objects)
    payment = objects[:payment] || objects["payment"] || {}
    payment_id = payment[:id] || payment["id"]
    return if payment_id.blank?

    original = CreditTransaction.where(transaction_type: "topup")
                                .where("metadata LIKE ?", "%#{payment_id}%").first
    unless original
      Rails.logger.warn("[FreemiusWebhook] Refund for unknown payment #{payment_id}")
      return
    end

    already_reversed = CreditTransaction.where(transaction_type: "refund")
                                        .where("metadata LIKE ?", "%#{payment_id}%").exists?
    return if already_reversed

    CreditTransaction.create!(
      wallet_id: original.wallet_id,
      transaction_type: "refund",
      amount_cents: -original.amount_cents.abs,
      metadata: { freemius_payment_id: payment_id }.to_json
    )
    Rails.logger.info("[FreemiusWebhook] Recorded refund for payment #{payment_id}")
  end

  # Syncs subscription lifecycle events to UserPlanSubscription.
  def handle_subscription_event(event, objects)
    subscription = objects[:subscription] || objects["subscription"] || {}
    freemius_id = subscription[:id] || subscription["id"]
    metadata = subscription[:metadata] || subscription["metadata"] || {}
    return if freemius_id.blank?

    record = UserPlanSubscription.find_by(freemius_subscription_id: freemius_id)
    # Fall back to person+listing lookup from metadata for the first event.
    if record.nil? && event == "subscription.created"
      person_id = metadata[:person_id] || metadata["person_id"]
      listing_id = metadata[:listing_id] || metadata["listing_id"]
      record = UserPlanSubscription.find_by(person_id: person_id, listing_id: listing_id, status: "active")
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
