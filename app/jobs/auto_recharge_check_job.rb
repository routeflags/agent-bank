# frozen_string_literal: true

# Checks all active subscription_with_overage subscriptions and triggers
# auto-recharge for wallets whose balance has fallen below the threshold.
#
# Schedule: runs daily via cron or Delayed::Job recurring plugin.
#
class AutoRechargeCheckJob < Struct.new(:community_id)

  include DelayedAirbrakeNotification

  # Required by Delayed::Job when using Struct-based jobs
  def before(job)
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    threshold = BillingConfig.auto_recharge_threshold_cents
    recharge_amount = BillingConfig.auto_recharge_amount_cents
    monthly_cap = BillingConfig.max_monthly_charge_cents

    subscriptions = UserPlanSubscription
      .where(status: "active", billing_model: "subscription_with_overage")
      .includes(person: :wallet)

    subscriptions = subscriptions.joins(:person).where(people: { community_id: community_id }) if community_id

    subscriptions.find_each do |subscription|
      wallet = subscription.person&.wallet
      next unless wallet
      next unless wallet.below_threshold?(threshold)

      wallet.auto_recharge!(
        recharge_amount,
        max_monthly_charge_cents: monthly_cap
      )
    rescue Wallet::PaymentMethodRequiredError => e
      Rails.logger.warn("[AutoRechargeCheckJob] Skipping subscription #{subscription.id}: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("[AutoRechargeCheckJob] Error for subscription #{subscription.id}: #{e.message}")
    end
  end
end
