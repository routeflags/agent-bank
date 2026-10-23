# frozen_string_literal: true

# 開発/テスト専用のペルソナ購入 API。
#
# POST /api/v1/dev/persona_purchases
#
# Freemius の実 API キーを投入せずに「購入→チャット利用」を検証するための
# 経路。実際の課金は行わず、購入済み状態（UserPlanSubscription）と初回トークンを
# 付与する。
#
# ガード（DevPersonaPurchase）:
#   * production では常に無効
#   * development / test でも LAMPREY_ENABLE_DEV_PURCHASE が真のときのみ有効
# 無効時は 404 を返し、本番ではエンドポイントの存在自体を見せない。
class API::V1::Dev::PersonaPurchasesController < ApplicationController
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
  before_action :ensure_dev_purchase_enabled

  # POST /api/v1/dev/persona_purchases
  #
  # params:
  #   listing_id - 購入するペルソナ（Listing）の ID
  #
  # 既に購入済みの場合は新規作成せず既存の subscription を 200 で返す。
  def create
    listing = Listing.find_by(id: params[:listing_id])

    unless listing
      return render json: { error: "ペルソナが見つかりません" }, status: :not_found
    end

    result = DevPersonaPurchase.grant!(person: current_user, listing: listing)

    render json: { persona_purchase: serialize_result(result) },
           status: result.duplicate? ? :ok : :created
  rescue DevPersonaPurchase::DisabledError => e
    # before_action で弾いている想定の保険。ゲート判定をすり抜けても付与しない。
    Rails.logger.warn("[DevPersonaPurchases] blocked: #{e.message}")
    render json: { error: "見つかりません" }, status: :not_found
  end

  private

  def ensure_authenticated
    unless current_user
      render json: { error: "ログインが必要です" }, status: :unauthorized
    end
  end

  # 開発購入が無効な環境では 404 を返す（本番に導線を広告しない）。
  def ensure_dev_purchase_enabled
    return if DevPersonaPurchase.enabled?

    render json: { error: "見つかりません" }, status: :not_found
  end

  # @param result [UserPlanSubscriptionService::Result]
  # @return [Hash]
  def serialize_result(result)
    subscription = result.subscription

    {
      subscription_id: subscription.id,
      listing_id: subscription.listing_id,
      person_id: subscription.person_id,
      status: subscription.status,
      billing_model: subscription.billing_model,
      duplicate: result.duplicate?
    }
  end
end
