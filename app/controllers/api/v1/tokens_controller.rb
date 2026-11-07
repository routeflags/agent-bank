# frozen_string_literal: true

# MCP（ローカル実行）用パーソナルアクセストークンの発行・一覧・失効 API（Issue #141）。
#
# 認証は当面 Devise セッション（Cookie）で行う。Web UI からの発行・失効用で、
# ローカルプロセスからの Bearer 認証は #142 がこのトークンを使って実装する。
# 平文トークンは発行時に一度だけ返し、一覧には digest も含めない。
class API::V1::TokensController < ApplicationController
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

  # GET /api/v1/tokens
  #
  # 本人のトークンだけを返す。平文も digest も含めない。
  def index
    tokens = current_user.api_tokens.order(created_at: :desc)
    render json: { api_tokens: tokens.map { |token| serialize_token(token) } }
  end

  # POST /api/v1/tokens
  #
  # 平文トークンを返すのはこのレスポンスだけ。以降は再表示できない。
  #
  # @param name [String] 利用者が付ける識別名
  # @param scopes [Array<String>] read / run（未指定は read のみ）
  def create
    token, raw_token = APIToken.issue!(
      person: current_user,
      name: params[:name].to_s,
      scopes: params.fetch(:scopes, ["read"])
    )

    render json: {
      raw_token: raw_token,
      api_token: serialize_token(token)
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /api/v1/tokens/:id
  #
  # 失効（論理削除）。本人のトークン以外は 404 を返す。
  def destroy
    token = current_user.api_tokens.find_by(id: params[:id])

    unless token
      return render json: { error: "トークンが見つかりません" }, status: :not_found
    end

    token.revoke!
    render json: { api_token: serialize_token(token) }
  end

  private

  def ensure_authenticated
    unless current_user
      render json: { error: "ログインが必要です" }, status: :unauthorized
    end
  end

  # 平文・digest は返さない。
  def serialize_token(token)
    {
      id: token.id,
      name: token.name,
      scopes: token.scope_list,
      last_used_at: token.last_used_at&.iso8601,
      expires_at: token.expires_at&.iso8601,
      revoked_at: token.revoked_at&.iso8601,
      daily_cost_limit_cents: token.daily_cost_limit_cents,
      created_at: token.created_at&.iso8601
    }
  end
end
