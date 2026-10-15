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
      # Creates a checkout session with the configured payment provider.
      # Freemius (Merchant of Record) is preferred when configured;
      # otherwise falls back to Stripe PaymentIntent for backward compatibility.
      # Returns a checkout_url (Freemius) or client_secret (Stripe) that the
      # frontend uses to complete the payment.
      def create
        amount_cents = params[:amount_cents].to_i

        unless valid_topup_amount?(amount_cents)
          return render json: {
            error: "金額は#{MIN_TOPUP_CENTS / 100}円〜#{MAX_TOPUP_CENTS / 100}円の間で指定してください"
          }, status: :unprocessable_entity
        end

        wallet = find_or_create_wallet!

        # 開発/テスト環境で決済キー未設定の場合、実カード決済の代わりに
        # デバッグ用の擬似 PaymentIntent を返す（ローカル開発でチャージ動作を検証するため）。
        if dev_mode_topup?
          return render json: {
            client_secret: dev_secret_for(amount_cents, wallet),
            payment_intent_id: dev_intent_id_for(amount_cents, wallet),
            amount_cents: amount_cents,
            dev_mode: true
          }
        end

        # Freemius (Merchant of Record) takes precedence when configured.
        if FreemiusClient.configured?
          return create_freemius_checkout(amount_cents, wallet)
        end

        intent = create_payment_intent(amount_cents, wallet)

        render json: {
          client_secret: intent.client_secret,
          payment_intent_id: intent.id,
          amount_cents: amount_cents,
          provider: "stripe"
        }
      rescue Stripe::InvalidRequestError => e
        Rails.logger.error("[WalletTopup] Stripe error creating PaymentIntent: #{e.message}")
        render json: { error: "決済の作成に失敗しました: #{e.message}" }, status: :unprocessable_entity
      rescue FreemiusClient::ApiError => e
        Rails.logger.error("[WalletTopup] Freemius error creating checkout: #{e.message}")
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

        # デバッグ用擬似 PaymentIntent（Stripe 不要）の場合
        if dev_intent?(intent_id)
          return confirm_dev_topup(intent_id)
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
          # metadata は {"stripe_payment_id":"..."} 形式で保存されるため、
          # 完全一致ではなく LIKE で検索する（JSON書式の差異に頑健）。
          already_credited = wallet.credit_transactions.where(
            transaction_type: "topup"
          ).where("metadata LIKE ?", "%#{intent.id}%").exists?

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

      # Creates a Freemius checkout session for the wallet top-up.
      # The buyer completes payment on Freemius; completion arrives via
      # webhook (FreemiusWebhooksController#payment_completed).
      def create_freemius_checkout(amount_cents, wallet)
        session = FreemiusClient.create_checkout(
          amount_cents: amount_cents,
          currency: (wallet.currency || BillingConfig.currency).upcase,
          user_id: current_user.id,
          wallet_id: wallet.id
        )

        render json: {
          checkout_url: session["checkout_url"],
          payment_id: session["payment_id"],
          amount_cents: amount_cents,
          provider: "freemius"
        }
      end

      # ── デバッグ用擬似決済（Stripe キー未設定時のローカル動作） ──
      #
      # 開発/テスト環境で Stripe API キーが設定されていない場合、
      # 実カード決済の代わりに Base64 エンコードした擬似 PaymentIntent を
      # 発行し、confirm 時に Wallet#topup! で直接チャージする。
      # これにより Stripe アカウントなしでもチャージ動作を検証できる。

      # 擬似決済を有効にするか（開発環境のみ + Stripeキー未設定）
      # テスト環境では Stripe パス（モック）を検証するため dev モードにしない。
      def dev_mode_topup?
        Rails.env.development? && !stripe_key_configured?
      end

      # Stripe API キーが設定されているか
      def stripe_key_configured?
        PaymentSettings.exists?(
          community_id: current_user.community_id,
          payment_gateway: "stripe",
          active: true
        ) || ENV["STRIPE_SECRET_KEY"].present?
      end

      # 擬似 PaymentIntent ID を生成（金額・ウォレット・ランダムトークンを埋め込む）
      # ランダムトークンを含めることで、同一金額の再チャージでも一意な ID になる
      def dev_intent_id_for(amount_cents, wallet)
        payload = {
          "uid" => current_user.id,
          "wid" => wallet.id,
          "amt" => amount_cents,
          "rnd" => SecureRandom.hex(6)
        }
        "dev_pi_#{Base64.urlsafe_encode64(payload.to_json, padding: false)}"
      end

      def dev_secret_for(amount_cents, wallet)
        "#{dev_intent_id_for(amount_cents, wallet)}_secret"
      end

      # 擬似 PaymentIntent ID かどうか
      def dev_intent?(intent_id)
        intent_id.to_s.start_with?("dev_pi_")
      end

      # 擬似決済を確定し、ウォレットをチャージする
      def confirm_dev_topup(intent_id)
        encoded = intent_id.delete_prefix("dev_pi_")
        payload = JSON.parse(Base64.urlsafe_decode64(encoded))

        unless payload["uid"] == current_user.id
          return render json: { error: "認証されていません" }, status: :forbidden
        end

        wallet = Wallet.find_by(id: payload["wid"])
        unless wallet
          return render json: { error: "ウォレットが見つかりません" }, status: :not_found
        end

        # 冪等性チェック: 同一擬似 PI で既にチャージ済みか
        # metadata は {"stripe_payment_id":"..."} 形式で保存されるため、
        # 完全一致ではなく LIKE で検索する（JSON書式の差異に頑健）。
        already_credited = wallet.credit_transactions.where(
          transaction_type: "topup"
        ).where("metadata LIKE ?", "%#{intent_id}%").exists?

        if already_credited
          return render json: {
            status: "ok",
            balance_cents: wallet.reload.balance_cents,
            amount_credited: 0,
            message: "既に処理済みです"
          }
        end

        wallet.topup!(payload["amt"], stripe_payment_id: intent_id)

        render json: {
          status: "ok",
          balance_cents: wallet.reload.balance_cents,
          amount_credited: payload["amt"],
          dev_mode: true
        }
      rescue ArgumentError, JSON::ParserError => e
        Rails.logger.error("[WalletTopup] Invalid dev intent: #{e.message}")
        render json: { error: "決済情報が不正です" }, status: :unprocessable_entity
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
