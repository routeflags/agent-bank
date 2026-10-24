# frozen_string_literal: true

# 本番のペルソナ購入 API（Issue #23、Issue #43 で Freemius 一本化）。
#
# POST /api/v1/persona_purchases
#
# Freemius ホスト型 Checkout（Merchant of Record、plan 単位）への URL を返す。
# サーバーは課金セッションを API で作らない（Freemius に任意金額の Checkout 作成
# API は存在しないため。Issue #43 調査を参照）。金額・通貨・購入者はサーバー側で
# 決定し、クライアントは listing_id しか指定できない（クライアント値を信用しない）。
#
# 決済完了は Webhook（FreemiusWebhooksController の persona_purchase 経路）で
# UserPlanSubscriptionService.create_for により購入権利として付与される。
# 本 API 自体は購入権利を作成しない。
#
# Freemius 未設定時（FREEMIUS_PRODUCT_ID / API_BEARER_AUTHORIZATION_TOKEN /
# plan 解決のいずれか缺け）は 503 + error_type: "purchase_not_configured" を返す
#（500 や無言の失敗にしない。既存挙動の回帰維持）。
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
  # 200: { checkout_url:, listing_id:, plan_id:, amount_cents:, provider: "freemius" }
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

    # 決済未設定（product/Bearer 缺け）は 503 で明示する（既存回帰維持）。
    unless FreemiusClient.configured?
      return render json: {
        error: "決済が未設定のため、購入機能は現在準備中です",
        error_type: "purchase_not_configured"
      }, status: :service_unavailable
    end

    # plan 解決ができない間は課金リンクを作れない。金額の自由指定は
    # Freemius に存在しないため、plan 未解決を 500 にせず 503 で明示する。
    plan_id = FreemiusClient.plan_id_for_listing(listing)
    if plan_id.blank?
      return render json: {
        error: "決済が未設定のため、購入機能は現在準備中です",
        error_type: "purchase_not_configured"
      }, status: :service_unavailable
    end

    # 金額・購入者はサーバー側で決定する（クライアント値は無視）。
    # checkout_url は local で組み立てる（Freemius への network 呼び出しなし）。
    checkout_url = FreemiusClient.build_hosted_checkout_url(
      plan_id: plan_id,
      user_email: buyer_email_for_checkout
    )

    render json: {
      checkout_url: checkout_url,
      listing_id: listing.id,
      plan_id: plan_id,
      amount_cents: listing.price_cents.to_i,
      provider: "freemius"
    }
  rescue FreemiusClient::ApiError => e
    # 設定不備・URL 組み立て失敗はクライアント入力の問題ではないため 502（422 ではない）。
    Rails.logger.error("[PersonaPurchases] Freemius error building checkout: #{e.message}")
    render json: {
      error: "決済ページの作成に失敗しました",
      error_type: "checkout_failed"
    }, status: :bad_gateway
  end

  private

  # Hosted checkout の user_email prefill 用。Sharetribe の Person は
  # emails テーブル経由（confirmed 優先）のため valid_email を使う。
  # 取得できなくても checkout 自体は継続できるので nil を許容する。
  def buyer_email_for_checkout
    return nil unless current_user.respond_to?(:valid_email)

    email = current_user.valid_email
    email.to_s.strip.presence
  rescue StandardError
    nil
  end

  def ensure_authenticated
    unless current_user
      render json: { error: "ログインが必要です" }, status: :unauthorized
    end
  end
end
