# frozen_string_literal: true

# Wallet top-up API controller (Issue #34, Issue #43 Freemius一本化).
#
# Provides dev-mode pseudo top-up only:
#   1. POST /api/v1/wallet_topup          → returns a dev_pi_* pseudo intent (dev only)
#   2. POST /api/v1/wallet_topup/confirm   → credits the wallet (dev intents only)
#
# Freemius hosted checkout does not support arbitrary amounts (plan-based only),
# so wallet top-up via Freemius is intentionally unsupported (see
# documents/guides/freemius_production_setup.md). Stripe paths were removed
# per owner policy (Freemius only). Sharetribe core Stripe settings
# (PaymentSettings etc.) are left untouched.
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

      # GET /api/v1/wallet_topup/status
      #
      # Returns whether wallet top-up is currently available and why.
      # The frontend uses this to keep the top-up button label in sync
      # with the actual payment configuration (Issue #34, Issue #43):
      #   * development → dev_mode pseudo-payment
      #   * otherwise → topup_enabled: false with reason payment_unconfigured
      #     (Freemius hosted checkout is plan-based and cannot charge an
      #     arbitrary amount; Stripe is not used per owner policy).
      # The payload mirrors #create so the button state always matches
      # what a top-up attempt would do.
      def status
        render json: topup_status_payload
      end

      # POST /api/v1/wallet_topup
      #
      # Creates a dev-mode pseudo intent in development. In any other
      # environment the arbitrary-amount top-up is unsupported (Freemius is
      # plan-based, Stripe is not used), so 503 payment_unconfigured is
      # returned. See documents/guides/freemius_production_setup.md.
      def create
        amount_cents = params[:amount_cents].to_i

        unless valid_topup_amount?(amount_cents)
          return render json: {
            error: "金額は#{MIN_TOPUP_CENTS / 100}円〜#{MAX_TOPUP_CENTS / 100}円の間で指定してください"
          }, status: :unprocessable_entity
        end

        wallet = find_or_create_wallet!

        # 開発環境では実カード決済の代わりにデバッグ用の擬似 PaymentIntent を
        # 返す（ローカル開発でチャージ動作を検証するため。開発用経路は残す）。
        if dev_mode_topup?
          return render json: {
            client_secret: dev_secret_for(amount_cents, wallet),
            payment_intent_id: dev_intent_id_for(amount_cents, wallet),
            amount_cents: amount_cents,
            dev_mode: true
          }
        end

        # Freemius ホスト型 Checkout は plan 単位で任意金額に対応しないため、
        # ウォレットの任意額チャージは提供しない。Stripe へはフォールバックしない
        #（オーナー方針: Freemius 一本）。代替案は文書に記録している。
        render json: {
          error: "決済が未設定のため、現在チャージできません",
          error_type: "payment_unconfigured",
          reason: "freemius_arbitrary_amount_unsupported"
        }, status: :service_unavailable
      end

      # POST /api/v1/wallet_topup/confirm
      #
      # Credits the wallet for dev-mode pseudo intents only.
      # Includes idempotency protection to prevent double-crediting on retries.
      def confirm
        intent_id = params[:payment_intent_id]

        unless intent_id.present?
          return render json: { error: "payment_intent_id は必須です" }, status: :bad_request
        end

        # デバッグ用擬似 PaymentIntent（開発用）の場合のみ受理する。
        if dev_intent?(intent_id)
          return confirm_dev_topup(intent_id)
        end

        # Freemius/Stripe の confirm 経路は提供しない（Issue #43）。
        render json: {
          error: "この環境では決済の確定は利用できません",
          error_type: "confirm_unsupported"
        }, status: :unprocessable_entity
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

      # Builds the top-up availability payload (see #status).
      # Mirrors #create so the button state always matches
      # what a top-up attempt would do.
      def topup_status_payload
        if dev_mode_topup?
          { topup_enabled: true, dev_mode: true, provider: "dev", reason: nil }
        else
          { topup_enabled: false, dev_mode: false, provider: nil, reason: "payment_unconfigured" }
        end
      end

      # ── デバッグ用擬似決済（開発環境のローカル動作。Issue #43 で残す） ──
      #
      # 開発環境では実カード決済の代わりに Base64 エンコードした擬似 PaymentIntent を
      # 発行し、confirm 時に Wallet#topup! で直接チャージする。
      # これにより決済アカウントなしでもチャージ動作を検証できる。

      # 擬似決済を有効にするか（開発環境のみ）。
      # テスト環境では dev モードにしない（spec が明示的に development を stub した場合のみ dev）。
      def dev_mode_topup?
        Rails.env.development?
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

        # Idempotent credit with row lock (see Wallet#topup!).
        credited = wallet.topup!(payload["amt"], stripe_payment_id: intent_id)

        if credited.nil?
          return render json: {
            status: "ok",
            balance_cents: wallet.reload.balance_cents,
            amount_credited: 0,
            message: "既に処理済みです"
          }
        end

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
    end
  end
end
