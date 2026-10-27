# frozen_string_literal: true

# Wallet top-up API controller (Issue #34, #43 Freemius一本化, #46 固定額プリペイド).
#
# Two paths (no arbitrary-amount Freemius checkout exists):
#   1. Fixed prepaid (production): POST with `plan_id` → hosted Checkout URL.
#      Credit amount comes solely from `FREEMIUS_TOPUP_PLAN_MAP`
#      (see FreemiusTopupPlans). Webhook credits `Wallet#topup!`.
#   2. Dev pseudo (development only): POST with `amount_cents` → dev_pi_* intent,
#      then POST /confirm credits the wallet. Kept for local verification.
#
# Arbitrary `amount_cents` in non-dev is rejected with 422 (Issue #46).
# Freemius hosted checkout does not support arbitrary amounts (plan-based only).
# Stripe paths were removed per owner policy (Freemius only). Sharetribe core
# Stripe settings (PaymentSettings etc.) are left untouched.
#
# Dev amount validation: 100円〜10,000円 (100–10,000 cents).
# Fixed prepaid credit validation: FreemiusTopupPlans (100〜100,000 yen).
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
      # with the actual payment configuration (Issue #34, #43, #46):
      #   * development → dev_mode pseudo-payment (amount_cents, no plan_id)
      #   * fixed prepaid (any env with Freemius + FX rate + TOPUP_MAP) →
      #     topup_enabled: true with denominations (plan_id / USD / JPY).
      #   * otherwise → topup_enabled: false with reason payment_unconfigured.
      # The payload mirrors #create so the button state always matches
      # what a top-up attempt would do.
      def status
        render json: topup_status_payload
      end

      # POST /api/v1/wallet_topup
      #
      # Fixed prepaid (Issue #46): accepts `plan_id`, returns a hosted
      # Checkout URL. Arbitrary `amount_cents` is rejected with 422 in
      # non-dev (Freemius has no arbitrary-amount checkout; Stripe is not
      # used per owner policy). Dev pseudo top-up (`amount_cents` →
      # dev_pi_* intent) is kept for local verification.
      # See documents/guides/freemius_production_setup.md.
      def create
        plan_id = params[:plan_id].to_s.strip
        return create_fixed_prepaid(plan_id) if plan_id.present?

        # No plan_id: legacy dev pseudo path (development only) or 422.
        # Any `amount_cents` outside dev is an arbitrary-amount request,
        # which Freemius cannot fulfil → 422 (not 503: it is a client
        # input problem, not a transient misconfiguration).
        if dev_mode_topup?
          return create_dev_pseudo
        end

        render json: {
          error: "チャージ金額は固定額プランから選択してください",
          error_type: "plan_id_required"
        }, status: :unprocessable_entity
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

      # Fixed prepaid checkout for a denomination plan (Issue #46).
      #
      # @param plan_id [String] validated denomination plan ID
      def create_fixed_prepaid(plan_id)
        credit_jpy = FreemiusTopupPlans.credit_for_plan(plan_id)
        if credit_jpy.nil?
          return render json: {
            error: "指定されたプランは利用できません",
            error_type: "invalid_plan"
          }, status: :unprocessable_entity
        end

        unless FreemiusClient.configured?
          Rails.logger.warn("[WalletTopup] Freemius unconfigured for fixed prepaid plan=#{plan_id}")
          return render json: {
            error: "決済が未設定のため、現在チャージできません",
            error_type: "payment_unconfigured",
            reason: "freemius_not_configured"
          }, status: :service_unavailable
        end

        unless FreemiusPricing.configured?
          Rails.logger.warn("[WalletTopup] FX rate unconfigured (#{FreemiusPricing::RATE_ENV_VAR} missing)")
          return render json: {
            error: "決済設定が不足しているため、現在チャージできません",
            error_type: "payment_unconfigured",
            reason: "fx_rate_unconfigured"
          }, status: :service_unavailable
        end

        unless FreemiusTopupPlans.configured?
          Rails.logger.warn("[WalletTopup] Topup plans unconfigured: #{FreemiusTopupPlans.validation_errors.first}")
          return render json: {
            error: "決済設定が不足しているため、現在チャージできません",
            error_type: "payment_unconfigured",
            reason: "topup_plans_unconfigured"
          }, status: :service_unavailable
        end

        # Hosted checkout is plan-based; the true charge is the Dashboard
        # plan price (USD). The yen credit comes solely from the map.
        # Issue #53: warn-only reverse-margin check (converted >= expected).
        # Normal margin (e.g. 600 yen vs $5.00) stays silent.
        # cancel_url (back button) returns to the site root; success redirect
        # is the Dashboard global (`GET /freemius/return`).
        amounts = FreemiusPricing.amounts_for_jpy(credit_jpy)
        FreemiusPricing.check_plan_price(plan_id, amounts[:amount_usd_cents])
        cancel_url = checkout_cancel_url_for_topup
        checkout_url = FreemiusClient.build_hosted_checkout_url(
          plan_id: plan_id,
          user_email: buyer_email_for_checkout,
          cancel_url: cancel_url
        )

        render json: {
          checkout_url: checkout_url,
          cancel_url: cancel_url,
          plan_id: plan_id,
          amount_cents: credit_jpy,
          credit_jpy: credit_jpy,
          amount_usd_cents: amounts[:amount_usd_cents],
          currency: amounts[:currency],
          fx_rate: amounts[:fx_rate],
          provider: "freemius"
        }
      rescue FreemiusPricing::RateMissingError => e
        Rails.logger.error("[WalletTopup] FX rate missing: #{e.message}")
        render json: {
          error: "決済設定が不足しているため、現在チャージできません",
          error_type: "payment_unconfigured",
          reason: "fx_rate_unconfigured"
        }, status: :service_unavailable
      rescue FreemiusClient::ApiError => e
        Rails.logger.error("[WalletTopup] Freemius error building checkout: #{e.message}")
        render json: {
          error: "決済ページの作成に失敗しました",
          error_type: "checkout_failed"
        }, status: :bad_gateway
      end

      # Legacy dev pseudo intent (development only, no plan_id).
      def create_dev_pseudo
        amount_cents = params[:amount_cents].to_i

        unless valid_topup_amount?(amount_cents)
          return render json: {
            error: "金額は#{MIN_TOPUP_CENTS / 100}円〜#{MAX_TOPUP_CENTS / 100}円の間で指定してください"
          }, status: :unprocessable_entity
        end

        wallet = find_or_create_wallet!

        # 開発環境では実カード決済の代わりにデバッグ用の擬似 PaymentIntent を
        # 返す（ローカル開発でチャージ動作を検証するため。開発用経路は残す）。
        render json: {
          client_secret: dev_secret_for(amount_cents, wallet),
          payment_intent_id: dev_intent_id_for(amount_cents, wallet),
          amount_cents: amount_cents,
          dev_mode: true
        }
      end

      # Builds the top-up availability payload (see #status).
      # Mirrors #create so the button state always matches
      # what a top-up attempt would do.
      def topup_status_payload
        fixed_available = FreemiusClient.configured? &&
                          FreemiusPricing.configured? &&
                          FreemiusTopupPlans.configured?
        denominations = fixed_available ? FreemiusTopupPlans.available_denominations : []
        fx_rate = FreemiusPricing.configured? ? FreemiusPricing.rate : nil

        if dev_mode_topup?
          {
            topup_enabled: true,
            dev_mode: true,
            provider: "dev",
            reason: nil,
            fixed_prepaid_available: fixed_available,
            denominations: denominations,
            currency: FreemiusPricing::CURRENCY,
            fx_rate: fx_rate
          }
        elsif fixed_available
          {
            topup_enabled: true,
            dev_mode: false,
            provider: "freemius",
            reason: nil,
            denominations: denominations,
            currency: FreemiusPricing::CURRENCY,
            fx_rate: fx_rate
          }
        else
          {
            topup_enabled: false,
            dev_mode: false,
            provider: nil,
            reason: "payment_unconfigured",
            denominations: [],
            currency: FreemiusPricing::CURRENCY,
            fx_rate: fx_rate
          }
        end
      end

      # Hosted checkout の back ボタン（`cancel_url`）はサイト基点に戻す
      # （wallet は出品に紐付かないため）。
      #
      # @return [String] absolute URL
      def checkout_cancel_url_for_topup
        "#{request.base_url}/"
      rescue StandardError
        request.base_url.to_s
      end

      # Hosted checkout の user_email prefill 用。Person は emails テーブル
      # 経由（confirmed 優先）のため valid_email を使う。取得できなくても
      # checkout 自体は継続できるので nil を許容する。
      def buyer_email_for_checkout
        return nil unless current_user.respond_to?(:valid_email)

        email = current_user.valid_email
        email.to_s.strip.presence
      rescue StandardError
        nil
      end

      # ── デバッグ用擬似決済（開発環境のローカル動作。Issue #43 で残す） ──
      #
      # 開発環境では実カード決済の代わりに Base64 エンコードした擬似 PaymentIntent を
      # 発行し、confirm 時に Wallet#topup! で直接チャージする。
      # これにより決済アカウントなしでもチャージ動作を検証できる。

      # 擬似決済を有効にするか。
      #
      # 実際の Freemius 設定（product / Bearer / レート / 額面 MAP）が揃っている場合は、
      # 開発環境でも本物の hosted Checkout を使う。揃っていないときだけ擬似決済に落ちる。
      #
      # 以前は `Rails.env.development?` だけで判定していたため、キーを投入しても
      # ローカルでは必ず擬似決済になり、実決済のデバッグができなかった。
      # テスト環境では常に false（spec が明示的に stub した場合のみ本物の経路を検証できる）。
      def dev_mode_topup?
        return false unless Rails.env.development?
        return false if FreemiusClient.configured? &&
                        FreemiusPricing.configured? &&
                        FreemiusTopupPlans.configured?

        true
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
