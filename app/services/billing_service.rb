# frozen_string_literal: true

# トークン単価課金＋出品者収益分配の請求サービス（Issue #59）
#
# 出品価格は 1M トークンあたりの単価（listings.price_cents、「円 / 100万トークン」）。
#   base（購入者の消費ポイント） = ceil(price_cents × total_tokens / 1_000_000)、最低 1
#   fee（プラットフォーム取り分） = floor(base × platform_commission_rate / 100)
#   payout（店子の受取） = base - fee（店子のウォレットへ seller_earning として付与）
# 上乗せなし: total_charge_cents = base。
#
class BillingService
  TOKENS_PER_MILLION = 1_000_000
  attr_reader :person, :subscription, :usage_record, :listing

  # @param person [Person] the user being billed
  # @param subscription [UserPlanSubscription, nil] active subscription (nil for pay-per-use)
  # @param usage_record [UsageRecord] the usage to bill for
  # @param listing [Listing, nil] the listing being used (unit price + seller lookup)
  def initialize(person:, subscription: nil, usage_record:, listing: nil)
    @person = person
    @subscription = subscription
    @usage_record = usage_record
    @listing = listing
  end

  # Execute billing for the recorded usage.
  #
  # @return [Hash] billing breakdown
  def process!
    billing_model = subscription&.billing_model

    case billing_model
    when "subscription", "subscription_with_overage"
      process_subscription_usage(subscription)
    when "token_based"
      process_pay_per_use
    when "pay_per_use", nil
      process_pay_per_use
    end
  end

  # Calculate the charge breakdown with platform fee and seller payout.
  #
  # @return [Hash] breakdown of charges
  def calculate_charges
    base_cost_cents = calculate_base_cost_cents
    platform_commission_pct = get_platform_commission_rate
    platform_commission_cents = base_cost_cents * platform_commission_pct / 100
    seller_payout_cents = base_cost_cents - platform_commission_cents

    {
      base_cost_cents: base_cost_cents,
      platform_commission_pct: platform_commission_pct,
      platform_commission_cents: platform_commission_cents,
      seller_payout_cents: seller_payout_cents,
      total_charge_cents: base_cost_cents,
      tokens: usage_record.total_tokens,
      billing_model: subscription&.billing_model || "pay_per_use"
    }
  end

  private

  # Calculate the buyer's consumption in points from the listing unit price.
  #
  # The listing price is the per-1M-token unit price. Rounds up so that
  # truncation can never make usage free (minimum 1). A listing without a
  # unit price (nil/0) bills 0 with no seller payout (price is mandatory
  # since Issue #52, so this only covers legacy rows).
  def calculate_base_cost_cents
    unit_price = listing&.price_cents
    return 0 unless unit_price && unit_price > 0

    tokens = usage_record.total_tokens.to_i
    [(unit_price * tokens + TOKENS_PER_MILLION - 1) / TOKENS_PER_MILLION, 1].max
  end

  # Get the platform commission rate from payment settings.
  def get_platform_commission_rate
    community_id = person.community_ids.first
    unless community_id
      Rails.logger.warn("[BillingService] Person #{person.id} has no community memberships")
      return 0
    end

    # First try payment_settings.platform_commission_rate
    ps = PaymentSettings.find_by(community_id: community_id)
    return ps.platform_commission_rate if ps&.platform_commission_rate

    # Fallback to payment_settings.commission_from_seller (existing Sharetribe field)
    ps&.commission_from_seller || 0
  end

  # Process pay-per-use billing and credit the seller payout atomically.
  # The payout is part of the same transaction: if the buyer deduction
  # raises, the seller credit rolls back with it.
  def process_pay_per_use
    charges = calculate_charges
    wallet = person.wallet
    raise "No wallet for person #{person.id}" unless wallet

    ActiveRecord::Base.transaction do
      if charges[:total_charge_cents] > 0
        wallet.deduct_for_usage!(charges[:total_charge_cents], tokens_used: usage_record.total_tokens)
      end
      usage_record.update!(
        charge_cents: charges[:total_charge_cents],
        billing_model: "pay_per_use",
        metadata: {
          base_cost_cents: charges[:base_cost_cents],
          platform_commission_pct: charges[:platform_commission_pct],
          platform_commission_cents: charges[:platform_commission_cents],
          seller_payout_cents: charges[:seller_payout_cents]
        }.to_json
      )
      grant_seller_earning!(charges)
    end
    charges
  end

  # Process subscription overage billing with the same fee/payout split.
  # Included tokens are free; only the overage is charged (no markup:
  # total = overage) and the payout (overage - fee) goes to the seller
  # in the same transaction.
  def process_subscription_usage(subscription)
    included = BillingConfig.included_tokens(subscription.billing_model.to_sym)
    per_token = BillingConfig.per_token_price_cents(subscription.billing_model.to_sym)
    platform_commission_pct = get_platform_commission_rate

    breakdown = nil
    ActiveRecord::Base.transaction do
      subscription.lock!
      current_usage = subscription.period_usage_tokens
      new_usage = current_usage + usage_record.total_tokens
      overage = [0, new_usage - included].max
      overage_charge = overage * per_token
      platform_commission_cents = overage_charge * platform_commission_pct / 100
      seller_payout_cents = overage_charge - platform_commission_cents

      subscription.update!(period_usage_tokens: new_usage)

      if overage_charge > 0
        wallet = person.wallet
        raise "No wallet for person #{person.id}" unless wallet

        wallet.deduct_for_usage!(overage_charge, tokens_used: usage_record.total_tokens)
      end

      usage_record.update!(
        charge_cents: overage_charge,
        billing_model: subscription.billing_model,
        metadata: {
          base_cost_cents: overage_charge,
          platform_commission_pct: platform_commission_pct,
          platform_commission_cents: platform_commission_cents,
          seller_payout_cents: seller_payout_cents,
          overage_tokens: overage,
          included_tokens: included
        }.to_json
      )

      breakdown = {
        base_cost_cents: overage_charge,
        platform_commission_pct: platform_commission_pct,
        platform_commission_cents: platform_commission_cents,
        seller_payout_cents: seller_payout_cents,
        total_charge_cents: overage_charge,
        tokens: usage_record.total_tokens,
        billing_model: subscription.billing_model
      }
      grant_seller_earning!(breakdown)
    end
    breakdown
  end

  # Credit the seller payout to the listing author's wallet.
  # No-op when there is no author or nothing to pay out (base 0 /
  # fee covering the whole base). Idempotent per usage_record.
  def grant_seller_earning!(charges)
    payout_cents = charges[:seller_payout_cents].to_i
    return if payout_cents <= 0

    seller = listing&.author
    return unless seller

    seller_wallet = seller.find_or_create_wallet!(community: listing.community)
    credited = seller_wallet.credit_seller_earning!(
      payout_cents,
      usage_record: usage_record,
      listing: listing,
      breakdown: charges
    )
    return unless credited

    Rails.logger.info(
      "[BillingService] Seller earning listing=#{listing.id} author=#{seller.id} " \
      "tokens=#{charges[:tokens]} base=#{charges[:base_cost_cents]}c " \
      "fee=#{charges[:platform_commission_cents]}c payout=#{payout_cents}c " \
      "usage_record=#{usage_record.id}"
    )
  end
end
