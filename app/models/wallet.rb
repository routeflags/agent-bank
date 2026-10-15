# frozen_string_literal: true

# == Schema Information
#
# Table name: wallets
#
#  id            :bigint           not null, primary key
#  person_id     :string(22)       not null
#  community_id  :integer          not null
#  balance_cents :integer          default(0), not null
#  currency      :string           default("USD"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_wallets_on_person_id_and_community_id  (person_id,community_id) UNIQUE
#

class Wallet < ApplicationRecord
  class InsufficientBalanceError < StandardError; end
  class PaymentMethodRequiredError < StandardError; end

  belongs_to :person
  belongs_to :community
  has_many :credit_transactions, dependent: :destroy

  validates :balance_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true

  # Add funds to this wallet via Stripe or Freemius.
  #
  # Idempotent per provider payment ID: repeated calls with the same
  # stripe_payment_id / freemius_payment_id credit only once. The check
  # and the credit run inside a row lock so concurrent duplicate
  # deliveries cannot double-credit.
  #
  # @param amount_cents [Integer] amount to credit (positive)
  # @param stripe_payment_id [String, nil] Stripe PaymentIntent ID for audit trail
  # @param freemius_payment_id [String, nil] Freemius payment ID for audit trail
  # @return [CreditTransaction, nil] the created record, or nil if already credited
  def topup!(amount_cents, stripe_payment_id: nil, freemius_payment_id: nil)
    transaction do
      lock!
      if already_credited?(stripe_payment_id: stripe_payment_id, freemius_payment_id: freemius_payment_id)
        return nil
      end

      increment!(:balance_cents, amount_cents)
      credit_transactions.create!(
        transaction_type: "topup",
        amount_cents: amount_cents,
        metadata: {
          stripe_payment_id: stripe_payment_id,
          freemius_payment_id: freemius_payment_id
        }.compact.to_json
      )
    end
  end

  # Reverse a previous top-up (e.g. Freemius payment.refunded).
  # Decrements the balance and records a refund entry atomically.
  # Idempotent per provider payment ID.
  #
  # @param freemius_payment_id [String, nil] Freemius payment ID to reverse
  # @param stripe_payment_id [String, nil] Stripe PaymentIntent ID to reverse
  # @return [CreditTransaction, nil] the refund record, or nil if already reversed / nothing to reverse
  def refund!(freemius_payment_id: nil, stripe_payment_id: nil)
    transaction do
      lock!
      original = find_credited_transaction(
        stripe_payment_id: stripe_payment_id, freemius_payment_id: freemius_payment_id
      )
      return nil unless original
      return nil if refund_recorded?(
        stripe_payment_id: stripe_payment_id, freemius_payment_id: freemius_payment_id
      )

      decrement!(:balance_cents, original.amount_cents.abs)
      credit_transactions.create!(
        transaction_type: "refund",
        amount_cents: -original.amount_cents.abs,
        metadata: {
          stripe_payment_id: stripe_payment_id,
          freemius_payment_id: freemius_payment_id
        }.compact.to_json
      )
    end
  end

  # Whether a top-up with the given provider payment ID was already recorded.
  def already_credited?(stripe_payment_id: nil, freemius_payment_id: nil)
    find_credited_transaction(
      stripe_payment_id: stripe_payment_id, freemius_payment_id: freemius_payment_id
    ).present?
  end

  # Whether a refund for the given provider payment ID was already recorded.
  def refund_recorded?(stripe_payment_id: nil, freemius_payment_id: nil)
    scope = credit_transactions.where(transaction_type: "refund")
    scope = scope_for_provider(scope,
                               stripe_payment_id: stripe_payment_id,
                               freemius_payment_id: freemius_payment_id)
    scope.exists?
  end

  private

  # Exact-match lookup of a top-up by provider payment ID.
  # Parses the JSON metadata instead of LIKE-substring matching, so
  # "fs_pay_1" never matches "fs_pay_10".
  def find_credited_transaction(stripe_payment_id: nil, freemius_payment_id: nil)
    candidates = credit_transactions.where(transaction_type: "topup").to_a
    candidates.find do |tx|
      meta = parse_metadata(tx.metadata)
      (stripe_payment_id.present? && meta["stripe_payment_id"] == stripe_payment_id) ||
        (freemius_payment_id.present? && meta["freemius_payment_id"] == freemius_payment_id)
    end
  end

  def scope_for_provider(scope, stripe_payment_id: nil, freemius_payment_id: nil)
    ids = [stripe_payment_id, freemius_payment_id].compact
    return scope.none if ids.empty?

    conditions = ids.map { |id| "metadata LIKE ?" }.join(" OR ")
    values = ids.map { |id| "%\"#{sanitize_like(id)}\"%" }
    scope.where(conditions, *values)
  end

  def sanitize_like(str)
    str.to_s.gsub(/[\\%_]/) { |m| "\\#{m}" }
  end

  def parse_metadata(raw)
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  public

  # -- Public wallet operations continue below --

  # Deduct funds for AI usage. Raises InsufficientBalanceError if balance is too low.
  # Uses row-level lock to prevent race conditions between concurrent deductions.
  #
  # @param amount_cents [Integer] amount to debit (positive value, stored as negative)
  # @param tokens_used [Integer] number of tokens consumed
  # @return [CreditTransaction] the created transaction record
  # @raise [InsufficientBalanceError] when balance < amount
  def deduct_for_usage!(amount_cents, tokens_used: 0)
    transaction do
      lock!
      reload
      raise InsufficientBalanceError, "Insufficient balance: #{balance_cents} < #{amount_cents}" if balance_cents < amount_cents

      decrement!(:balance_cents, amount_cents)
      credit_transactions.create!(
        transaction_type: "usage_deduction",
        amount_cents: -amount_cents,
        metadata: { tokens_used: tokens_used }.to_json
      )
    end
  end

  # Automatically recharge from Stripe when balance drops below threshold.
  # Enforces a monthly spending cap to prevent runaway charges.
  #
  # @param recharge_amount_cents [Integer] target recharge amount
  # @param max_monthly_charge_cents [Integer, nil] monthly cap for auto-recharges
  # @return [Boolean] true if recharge succeeded, false otherwise
  def auto_recharge!(recharge_amount_cents, max_monthly_charge_cents: nil)
    recharge_amount_cents = apply_monthly_cap(recharge_amount_cents, max_monthly_charge_cents)
    return false if recharge_amount_cents <= 0

    payment_method = person&.default_payment_method
    raise PaymentMethodRequiredError, "No default payment method for person #{person_id}" unless payment_method

    result = Stripe::PaymentIntent.create(
      amount: recharge_amount_cents,
      currency: currency.downcase,
      customer: person.stripe_customer_id,
      payment_method: payment_method.stripe_payment_method_id,
      confirm: true,
      off_session: true,
      description: "Auto-recharge for wallet",
      idempotency_key: "auto_recharge_#{id}_#{Time.current.to_i}"
    )

    if result.status == "succeeded"
      # Create transaction FIRST with Stripe reference, THEN increment balance
      # to ensure audit trail exists before balance changes
      transaction do
        credit_transactions.create!(
          transaction_type: "auto_recharge",
          amount_cents: recharge_amount_cents,
          metadata: {
            stripe_payment_intent_id: result.id,
            triggered_by: "auto_recharge"
          }.to_json
        )
        increment!(:balance_cents, recharge_amount_cents)
      end
      true
    else
      false
    end
  rescue Stripe::CardError => e
    Rails.logger.error("[Wallet] Auto-recharge failed for wallet #{id}: #{e.message}")
    false
  end

  # Check whether the balance has fallen below a threshold.
  #
  # @param threshold_cents [Integer] threshold in cents
  # @return [Boolean]
  def below_threshold?(threshold_cents)
    balance_cents < threshold_cents
  end

  private

  # Reduce recharge_amount_cents to not exceed the remaining monthly cap.
  #
  # @param recharge_amount_cents [Integer]
  # @param max_monthly_charge_cents [Integer, nil]
  # @return [Integer] adjusted recharge amount
  def apply_monthly_cap(recharge_amount_cents, max_monthly_charge_cents)
    return recharge_amount_cents unless max_monthly_charge_cents

    month_total = credit_transactions
      .where(transaction_type: "auto_recharge")
      .where("created_at >= ?", Time.current.beginning_of_month)
      .sum(:amount_cents)

    remaining = max_monthly_charge_cents - month_total
    [recharge_amount_cents, remaining].min
  end
end
