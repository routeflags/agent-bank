# frozen_string_literal: true

# Creates a UserPlanSubscription and assigns initial tokens when a persona is purchased.
#
# This service is the single entry point for purchase → subscription linkage.
# It is idempotent: calling it twice for the same person+listing returns the
# existing subscription without creating duplicates.
#
# Usage:
#   result = UserPlanSubscriptionService.create_on_purchase(transaction)
#   result.subscription  # => UserPlanSubscription
#   result.wallet        # => Wallet (with initial tokens)
#   result.duplicate?    # => true if subscription already existed
#
class UserPlanSubscriptionService
  Result = Struct.new(:subscription, :wallet, :duplicate?, keyword_init: true)

  # Main entry point. Call this when a Transaction reaches "completed" state.
  #
  # @param transaction [Transaction] the completed purchase transaction
  # @return [Result] the result containing subscription, wallet, and duplicate flag
  # @raise [ActiveRecord::RecordInvalid] if subscription or wallet creation fails
  def self.create_on_purchase(transaction)
    new(transaction).call
  end

  def initialize(transaction)
    @transaction = transaction
    @listing = transaction.listing
    @person = transaction.buyer
  end

  def call
    # Check for existing active subscription (idempotency guard)
    existing = UserPlanSubscription.find_by(
      person: @person,
      listing: @listing,
      status: "active"
    )

    if existing
      return Result.new(
        subscription: existing,
        wallet: @person.wallet,
        duplicate?: true
      )
    end

    ActiveRecord::Base.transaction do
      subscription = create_subscription!
      wallet = assign_initial_tokens!

      Result.new(
        subscription: subscription,
        wallet: wallet,
        duplicate?: false
      )
    end
  end

  private

  # Creates an active UserPlanSubscription for the buyer ↔ listing pair.
  #
  # The billing_model is determined server-side based on whether a subscription
  # already exists (including cancelled ones) to decide between
  # "subscription_with_overage" and "token_based".
  #
  # @return [UserPlanSubscription]
  def create_subscription!
    billing_model = determine_billing_model

    UserPlanSubscription.create!(
      person: @person,
      listing: @listing,
      billing_model: billing_model,
      status: "active",
      current_period_start: Time.current,
      current_period_end: 1.year.from_now
    )
  end

  # Determines the billing model based on this person's history with this listing.
  # If the person has any prior subscription (even cancelled), use overage model.
  # Otherwise, use the base token-based model.
  #
  # @return [String]
  def determine_billing_model
    has_prior_subscription = UserPlanSubscription.exists?(
      person: @person,
      listing: @listing
    )

    has_prior_subscription ? "subscription_with_overage" : "token_based"
  end

  # Creates a Wallet if needed, then credits the included tokens.
  #
  # @return [Wallet]
  def assign_initial_tokens!
    wallet = find_or_create_wallet!
    included_tokens = BillingConfig.included_tokens(:subscription)
    per_token_cents = BillingConfig.per_token_price_cents(:subscription)
    initial_amount_cents = included_tokens * per_token_cents

    wallet.topup!(initial_amount_cents, stripe_payment_id: "initial_purchase_#{@transaction.id}")
    wallet
  end

  # Finds or creates a Wallet for the buyer.
  # Wallets are scoped to person+community (unique index).
  # Delegates to Person#find_or_create_wallet! to centralize wallet creation logic.
  #
  # @return [Wallet]
  def find_or_create_wallet!
    @person.find_or_create_wallet!(
      community: @listing.community,
      currency: @listing.currency
    )
  end
end
