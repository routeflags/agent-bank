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

  # Add funds to this wallet via Stripe.
  #
  # @param amount_cents [Integer] amount to credit (positive)
  # @param stripe_payment_id [String, nil] Stripe PaymentIntent ID for audit trail
  # @return [CreditTransaction] the created transaction record
  def topup!(amount_cents, stripe_payment_id: nil)
    transaction do
      increment!(:balance_cents, amount_cents)
      credit_transactions.create!(
        transaction_type: "topup",
        amount_cents: amount_cents,
        metadata: { stripe_payment_id: stripe_payment_id }.to_json
      )
    end
  end

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
