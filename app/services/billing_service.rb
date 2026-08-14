# frozen_string_literal: true

# Routes billing logic to the correct model after AI usage is recorded.
#
# Usage:
#   BillingService.new(person: person, subscription: sub, usage_record: record).process!
#
# The service inspects the subscription's billing_model and dispatches to:
#   - subscription / subscription_with_overage → overage-only charge
#   - pay_per_use / nil → full-amount charge from wallet
#
class BillingService
  attr_reader :person, :subscription, :usage_record

  # @param person [Person] the user being billed
  # @param subscription [UserPlanSubscription, nil] active subscription (nil for pay-per-use)
  # @param usage_record [UsageRecord] the usage to bill for
  def initialize(person:, subscription: nil, usage_record:)
    @person = person
    @subscription = subscription
    @usage_record = usage_record
  end

  # Execute billing for the recorded usage.
  #
  # @return [Boolean] true if billing succeeded
  def process!
    billing_model = subscription&.billing_model

    case billing_model
    when "subscription", "subscription_with_overage"
      process_subscription_usage(subscription)
    when "pay_per_use", nil
      process_pay_per_use
    end
  end

  private

  # Model 2: Pure pay-per-use — charge wallet for all tokens.
  def process_pay_per_use
    charge_amount = BillingConfig.pay_per_use_per_token_price_cents * usage_record.total_tokens

    wallet = person.wallet
    raise "No wallet for person #{person.id}" unless wallet

    ActiveRecord::Base.transaction do
      wallet.deduct_for_usage!(charge_amount, tokens_used: usage_record.total_tokens)
      usage_record.update!(
        charge_cents: charge_amount,
        billing_model: "pay_per_use"
      )
    end
    true
  end

  # Models 1 & 3: Subscription — only charge for overage beyond included tokens.
  def process_subscription_usage(subscription)
    included = BillingConfig.included_tokens(subscription.billing_model.to_sym)
    per_token = BillingConfig.per_token_price_cents(subscription.billing_model.to_sym)

    ActiveRecord::Base.transaction do
      # Lock subscription to prevent race conditions on period_usage_tokens
      subscription.lock!

      # Calculate overage BEFORE incrementing to avoid inflated reads
      current_usage = subscription.period_usage_tokens
      new_usage = current_usage + usage_record.total_tokens
      overage = [0, new_usage - included].max
      overage_charge = overage * per_token

      # Now increment
      subscription.update!(period_usage_tokens: new_usage)

      if overage_charge > 0
        wallet = person.wallet
        raise "No wallet for person #{person.id}" unless wallet
        wallet.deduct_for_usage!(overage_charge, tokens_used: usage_record.total_tokens)
      end

      usage_record.update!(
        charge_cents: overage_charge,
        billing_model: subscription.billing_model
      )
    end
    true
  end
end
