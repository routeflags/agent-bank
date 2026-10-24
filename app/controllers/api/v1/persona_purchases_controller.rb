# frozen_string_literal: true

# 本番のペルソナ購入 API（Issue #23）。
#
# POST /api/v1/persona_purchases
#
# Freemius Checkout（Merchant of Record）のセッションを作成し、checkout_url を返す。
# 金額・通貨・購入者はサーバー側で決定し、クライアントは listing_id しか指定できない
#（クライアント値を信用しない）。
#
# 決済完了は Webhook（FreemiusWebhooksController#handle_payment_completed の
# persona_purchase 経路）で UserPlanSubscriptionService.create_for により
# 購入権利として付与される。本 API 自体は購入権利を作成しない。
#
# Freemius 未設定時（FREEMIUS_API_KEY 未投入）は 503 +
# error_type: "purchase_not_configured" を返す（500 や無言の失敗にしない）。
class API::V1::PersonaPurchasesController < ApplicationController
  # API controller — CSRF token not needed (authenticated via Devise session/cookie)
  skip_before_action :verify_authenticity_token

  # Same filter surface as API::V1::ChatSessionsController.
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

  # POST /api/v1/persona_purchases
  #
  # params:
  #   listing_id - 購入するペルソナ（Listing）の ID（これ以外は受け付けない）
  #
  # 200: { checkout_url:, payment_id:, listing_id:, amount_cents:, provider: "freemius" }
  # 200: { status: "already_purchased" }（active な購入権利がある場合は Checkout を作らない）
  # 401 / 404 / 422 / 503 / 502: 下記コメント参照
  def create
    listing = Listing.find_by(id: params[:listing_id])

    unless listing
      return render json: {
        error: "ペルソナが見つかりません",
        error_type: "listing_not_found"
      }, status: :not_found
    end

    if listing.free_to_use?
      return render json: {
        error: "このペルソナは無料です。購入は不要です",
        error_type: "free_listing"
      }, status: :unprocessable_entity
    end

    # 購入済みなら Checkout を作らず既存の購入権利を返す（二重決済の防止）。
    if UserPlanSubscription.exists?(person: current_user, listing: listing, status: "active")
      return render json: {
        status: "already_purchased",
        listing_id: listing.id,
        provider: "freemius"
      }
    end

    # 決済未設定（FREEMIUS_API_KEY 未投入など）は 503 で明示する。
    unless FreemiusClient.configured?
      return render json: {
        error: "決済が未設定のため、購入機能は現在準備中です",
        error_type: "purchase_not_configured"
      }, status: :service_unavailable
    end

    # 金額・通貨・購入者はサーバー側で決定する（クライアント値は無視）。
    session = FreemiusClient.create_persona_purchase_checkout(
      amount_cents: listing.price_cents.to_i,
      currency: (listing.currency || BillingConfig.currency).upcase,
      user_id: current_user.id,
      listing_id: listing.id
    )

    unless session["checkout_url"].present?
      raise FreemiusClient::ApiError, "Freemius checkout response missing checkout_url"
    end

    render json: {
      checkout_url: session["checkout_url"],
      payment_id: session["payment_id"],
      listing_id: listing.id,
      amount_cents: listing.price_cents.to_i,
      provider: "freemius"
    }
  rescue FreemiusClient::ApiError => e
    # Freemius 側の障害はクライアント入力の問題ではないため 502（422 ではない）。
    Rails.logger.error("[PersonaPurchases] Freemius error creating checkout: #{e.message}")
    render json: {
      error: "決済ページの作成に失敗しました",
      error_type: "checkout_failed"
    }, status: :bad_gateway
  end

  private

  def ensure_authenticated
    unless current_user
      render json: { error: "ログインが必要です" }, status: :unauthorized
    end
  end
end
