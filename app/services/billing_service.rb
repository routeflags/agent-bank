# frozen_string_literal: true

# 双方向コミッション対応の請求サービス
#
# Model A (AI Direct):
#   ユーザー請求額 = トークン原価 × (1 + プラットフォームコミッション%)
#
# Model B (Seller Persona):
#   ユーザー請求額 = 出品ペルソナ価格 × (1 + 出品者コミッション% + プラットフォームコミッション%)
#
class BillingService
  attr_reader :person, :subscription, :usage_record, :listing

  # @param person [Person] the user being billed
  # @param subscription [UserPlanSubscription, nil] active subscription (nil for pay-per-use)
  # @param usage_record [UsageRecord] the usage to bill for
  # @param listing [Listing, nil] the listing being used (for seller commission lookup)
  def initialize(person:, subscription: nil, usage_record:, listing: nil)
    @person = person
    @subscription = subscription
    @usage_record = usage_record
    @listing = listing
  end

  # Execute billing for the recorded usage.
  #
  # @return [BillingResult] billing breakdown
  def process!
    billing_model = subscription&.billing_model

    case billing_model
    when "subscription", "subscription_with_overage"
      process_subscription_usage(subscription)
    when "pay_per_use", nil
      process_pay_per_use
    end
  end

  # Calculate the total charge amount with commissions.
  #
  # @return [Hash] breakdown of charges
  def calculate_charges
    base_cost_cents = calculate_base_cost_cents
    platform_commission_pct = get_platform_commission_rate
    seller_commission_pct = get_seller_commission_rate

    platform_commission_cents = (base_cost_cents * platform_commission_pct / 100.0).to_i
    seller_commission_cents = (base_cost_cents * seller_commission_pct / 100.0).to_i
    total_charge_cents = base_cost_cents + platform_commission_cents + seller_commission_cents

    {
      base_cost_cents: base_cost_cents,
      platform_commission_pct: platform_commission_pct,
      platform_commission_cents: platform_commission_cents,
      seller_commission_pct: seller_commission_pct,
      seller_commission_cents: seller_commission_cents,
      total_charge_cents: total_charge_cents,
      tokens: usage_record.total_tokens,
      billing_model: subscription&.billing_model || "pay_per_use"
    }
  end

  private

  # Calculate the base cost (before commissions) based on the billing model.
  #
  # Model A (AI Direct): AI token cost per token × tokens
  # Model B (Seller Persona): Persona price (per interaction, fixed)
  def calculate_base_cost_cents
    listing_price = listing&.price_cents

    if listing_price && listing_price > 0
      # Model B: Persona price is the total per-interaction cost
      listing_price
    else
      # Model A: AI model cost per token × total tokens
      ai_model = usage_record.ai_model
      if ai_model
        cost = ai_model.estimate_cost(usage_record.input_tokens, usage_record.output_tokens)
        (cost * 100).to_i # Convert dollars to cents
      else
        0
      end
    end
  end

  # Get the platform commission rate from payment settings.
  def get_platform_commission_rate
    # First try payment_settings.platform_commission_rate
    ps = PaymentSettings.find_by(community_id: person.community_ids.first)
    return ps.platform_commission_rate if ps&.platform_commission_rate

    # Fallback to payment_settings.commission_from_seller (existing Sharetribe field)
    ps&.commission_from_seller || 0
  end

  # Get the seller commission rate from the listing.
  # Only applies to Model B (Seller Persona).
  def get_seller_commission_rate
    listing&.seller_commission_rate || 0
  end

  # Process pay-per-use billing with dual commissions.
  def process_pay_per_use
    charges = calculate_charges
    wallet = person.wallet
    raise "No wallet for person #{person.id}" unless wallet

    ActiveRecord::Base.transaction do
      wallet.deduct_for_usage!(charges[:total_charge_cents], tokens_used: usage_record.total_tokens)
      usage_record.update!(
        charge_cents: charges[:total_charge_cents],
        billing_model: "pay_per_use",
        metadata: {
          base_cost_cents: charges[:base_cost_cents],
          platform_commission_cents: charges[:platform_commission_cents],
          seller_commission_cents: charges[:seller_commission_cents],
          platform_commission_pct: charges[:platform_commission_pct],
          seller_commission_pct: charges[:seller_commission_pct]
        }.to_json
      )
    end
    charges
  end

  # Process subscription billing with dual commissions.
  def process_subscription_usage(subscription)
    charges = calculate_charges
    included = BillingConfig.included_tokens(subscription.billing_model.to_sym)
    per_token = BillingConfig.per_token_price_cents(subscription.billing_model.to_sym)

    ActiveRecord::Base.transaction do
      subscription.lock!
      current_usage = subscription.period_usage_tokens
      new_usage = current_usage + usage_record.total_tokens
      overage = [0, new_usage - included].max
      overage_charge = overage * per_token

      # Add commissions to overage charge
      platform_commission_pct = get_platform_commission_rate
      seller_commission_pct = get_seller_commission_rate
      total_overage_charge = overage_charge +
        (overage_charge * platform_commission_pct / 100.0).to_i +
        (overage_charge * seller_commission_pct / 100.0).to_i

      subscription.update!(period_usage_tokens: new_usage)

      if total_overage_charge > 0
        wallet = person.wallet
        raise "No wallet for person #{person.id}" unless wallet
        wallet.deduct_for_usage!(total_overage_charge, tokens_used: usage_record.total_tokens)
      end

      usage_record.update!(
        charge_cents: total_overage_charge,
        billing_model: subscription.billing_model,
        metadata: {
          base_cost_cents: overage_charge,
          platform_commission_cents: (overage_charge * platform_commission_pct / 100.0).to_i,
          seller_commission_cents: (overage_charge * seller_commission_pct / 100.0).to_i,
          overage_tokens: overage,
          included_tokens: included
        }.to_json
      )
    end
    charges
  end
end
