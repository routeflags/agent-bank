# frozen_string_literal: true

# Wallet top-up API controller.
#
# Provides two-step Stripe-backed wallet top-up:
#   1. POST /api/v1/wallet_topup          → creates a Stripe PaymentIntent
#   2. POST /api/v1/wallet_topup/confirm   → verifies the PaymentIntent and credits the wallet
#
# Amount validation: 100円〜10,000円 (100–10,000 cents).
#
module API
  module V1
    class WalletTopupController < ApplicationController
      # API controller — CSRF token not needed (authenticated via Devise session/cookie)
      skip_before_action :verify_authenticity_token

      skip_before_action :fetch_community,
                         :fetch_community_plan_expiration_status,
                         :perform_redirect,
                         :initialize_feature_flags,
                         :save_current_host_with_port,
                         :fetch_community_membership,
                         :redirect_removed_locale,
                         :set_locale,
                         :redirect_locale_param,
                         :setup_seo_service,
                         :fetch_community_admin_status,
                         :warn_about_missing_payment_info,
                         :set_homepage_path,
                         :maintenance_warning,
                         :cannot_access_if_banned,
                         :cannot_access_without_confirmation,
                         :ensure_consent_given,
                         :ensure_user_belongs_to_community,
                         :set_display_expiration_notice,
                         :setup_intercom_user,
                         :setup_custom_footer,
                         :disarm_custom_head_script

      before_action :ensure_authenticated

      MIN_TOPUP_CENTS = 100
      MAX_TOPUP_CENTS = 10_000

      # GET /api/v1/wallet_topup/balance
      #
      # Returns the current wallet balance for the authenticated user.
      # Creates a wallet with zero balance if none exists.
      def balance
        wallet = find_or_create_wallet!

        render json: {
          balance_cents: wallet.balance_cents,
          currency: wallet.currency
        }
      end

      # POST /api/v1/wallet_topup
      #
      # Creates a Stripe PaymentIntent for the requested amount.
      # Returns a client_secret that the frontend uses to complete the payment.
      def create
        amount_cents = params[:amount_cents].to_i

        unless valid_topup_amount?(amount_cents)
          return render json: {
            error: "金額は#{MIN_TOPUP_CENTS / 100}円〜#{MAX_TOPUP_CENTS / 100}円の間で指定してください"
          }, status: :unprocessable_entity
        end

        wallet = find_or_create_wallet!

        intent = create_payment_intent(amount_cents, wallet)

        render json: {
          client_secret: intent.client_secret,
          payment_intent_id: intent.id,
          amount_cents: amount_cents
        }
      rescue Stripe::InvalidRequestError => e
        Rails.logger.error("[WalletTopup] Stripe error creating PaymentIntent: #{e.message}")
        render json: { error: "決済の作成に失敗しました: #{e.message}" }, status: :unprocessable_entity
      end

      # POST /api/v1/wallet_topup/confirm
      #
      # Verifies the PaymentIntent status and credits the wallet if succeeded.
      # Includes idempotency protection to prevent double-crediting on retries.
      def confirm
        intent_id = params[:payment_intent_id]

        unless intent_id.present?
          return render json: { error: "payment_intent_id は必須です" }, status: :bad_request
        end

        intent = Stripe::PaymentIntent.retrieve(intent_id)

        unless intent.metadata&.dig("user_id") == current_user.id
          return render json: { error: "認証されていません" }, status: :forbidden
        end

        if intent.status == "succeeded"
          wallet = Wallet.find_by(id: intent.metadata["wallet_id"])

          unless wallet
            return render json: { error: "ウォレットが見つかりません" }, status: :not_found
          end

          # 冪等性チェック: 同一 PaymentIntent で既にチャージ済みか確認
          already_credited = wallet.credit_transactions.exists?(
            transaction_type: "topup",
            metadata: "\"stripe_payment_id\":\"#{intent.id}\""
          )

          if already_credited
            return render json: {
              status: "ok",
              balance_cents: wallet.reload.balance_cents,
              amount_credited: 0,
              message: "既に処理済みです"
            }
          end

          wallet.topup!(intent.amount, stripe_payment_id: intent.id)

          render json: {
            status: "ok",
            balance_cents: wallet.reload.balance_cents,
            amount_credited: intent.amount
          }
        else
          render json: {
            error: "決済が完了していません",
            payment_status: intent.status
          }, status: :unprocessable_entity
        end
      rescue Stripe::InvalidRequestError => e
        Rails.logger.error("[WalletTopup] Stripe error retrieving PaymentIntent: #{e.message}")
        render json: { error: "決済情報の取得に失敗しました" }, status: :unprocessable_entity
      end

      private

      def ensure_authenticated
        unless current_user
          render json: { error: "ログインが必要です" }, status: :unauthorized
        end
      end

      # Validates the topup amount is within the allowed range.
      #
      # @param amount_cents [Integer]
      # @return [Boolean]
      def valid_topup_amount?(amount_cents)
        amount_cents >= MIN_TOPUP_CENTS && amount_cents <= MAX_TOPUP_CENTS
      end

      # Finds or creates a wallet for the current user.
      # Delegates to Person#find_or_create_wallet! for consistent wallet creation.
      #
      # @return [Wallet]
      def find_or_create_wallet!
        current_user.find_or_create_wallet!(community: current_user.community)
      end

      # Creates a Stripe PaymentIntent for the wallet top-up.
      #
      # @param amount_cents [Integer] the top-up amount in cents
      # @param wallet [Wallet] the target wallet
      # @return [Stripe::PaymentIntent]
      def create_payment_intent(amount_cents, wallet)
        # Retrieve Stripe API key from payment settings (block form ensures restore)
        configure_stripe_api! do
          Stripe::PaymentIntent.create(
            amount: amount_cents,
            currency: (wallet.currency || BillingConfig.currency).downcase,
            customer: current_user.stripe_customer_id,
            metadata: {
              user_id: current_user.id,
              wallet_id: wallet.id,
              community_id: current_user.community_id,
              type: "wallet_topup"
            },
            description: "Wallet top-up for #{current_user.id}"
          )
        end
      end

      # Configures the Stripe API key from the community's payment settings.
      # Falls back to ENV['STRIPE_SECRET_KEY'] if no payment settings exist.
      #
      # Thread-safe: saves and restores Stripe.api_key to prevent race conditions
      # in Puma's multi-threaded environment.
      def configure_stripe_api!
        previous_key = Stripe.api_key
        community = current_user.community
        payment_settings = PaymentSettings.find_by(
          community_id: community.id,
          payment_gateway: "stripe",
          active: true
        )

        if payment_settings
          Stripe.api_key = TransactionService::Store::PaymentSettings.decrypt_value(
            payment_settings.api_private_key,
            payment_settings.key_encryption_padding
          )
        elsif ENV["STRIPE_SECRET_KEY"].present?
          Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
        else
          raise "No Stripe API key configured for community #{community.id}"
        end

        yield if block_given?
      ensure
        Stripe.api_key = previous_key
      end
    end
  end
end
