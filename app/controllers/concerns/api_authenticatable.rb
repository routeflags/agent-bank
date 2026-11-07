# frozen_string_literal: true

# /api/v1 配下の JSON API 共通の認証・認可 concern（Issue #142）。
#
# 認証の順序:
#   1. `Authorization: Bearer <token>` があれば `APIToken` で認証し、
#      warden（Devise）と `@current_user` をトークンの所有者に揃える
#   2. ヘッダが無ければ何もしない = 従来どおり Devise セッション（Cookie）
#
# トークン認証はステートレスなのでセッションへ保存しない
# （`sign_in(person, store: false)`）。Bearer と Cookie が同時に付いた場合は
# Bearer を優先する。
#
# 使い方:
#   class API::V1::ExampleController < ApplicationController
#     include APIAuthenticatable
#     api_requires_scope :run   # 省略時は read
#   end
#
# 認証エラーのレスポンス:
#   401 {"error":"invalid_token"}    未登録・失効・期限切れのトークン
#   401 {"error":"ログインが必要です"} Bearer も Cookie も無い
#   403 {"error":"insufficient_scope"} scope 不足
module APIAuthenticatable
  extend ActiveSupport::Concern

  include ActionController::HttpAuthentication::Token::ControllerMethods

  # `ApplicationController` が HTML ページ向けに用意している before_action。
  # API は community も locale もレイアウトも使わないため外す。
  #
  # 従来はこのリストが API コントローラごとに複製されていた。フィルタの
  # 追加・削除はここだけを直せばよい。
  HTML_ONLY_FILTERS = %i[
    fetch_community
    fetch_community_plan_expiration_status
    perform_redirect
    initialize_feature_flags
    save_current_host_with_port
    fetch_community_membership
    redirect_removed_locale
    set_locale
    redirect_locale_param
    setup_seo_service
    fetch_community_admin_status
    warn_about_missing_payment_info
    set_homepage_path
    maintenance_warning
    cannot_access_if_banned
    cannot_access_without_confirmation
    ensure_consent_given
    ensure_user_belongs_to_community
    set_display_expiration_notice
    setup_intercom_user
    setup_custom_footer
    disarm_custom_head_script
  ].freeze

  # 最終使用日時を書き換える最短間隔。認証は全リクエストで走るため、
  # 毎回 UPDATE すると読み取りだけの API でも書き込みが発生する。
  LAST_USED_AT_INTERVAL = 1.minute

  included do
    # API は JSON のみで CSRF トークンを送らない。
    skip_before_action :verify_authenticity_token
    skip_before_action(*HTML_ONLY_FILTERS)

    # トークン認証時に要求するスコープ（既定は read）。
    class_attribute :api_required_scope, instance_writer: false, default: "read"

    before_action :authenticate_api_token!
    before_action :ensure_authenticated
    before_action :ensure_api_scope
  end

  class_methods do
    # トークン認証時に要求するスコープを宣言する。
    #
    # `run` を要求するアクション（#144 の実行系）と `read` で足りる参照系を
    # コントローラ単位で分けるための入口。Cookie 認証には scope が無いので
    # この宣言はトークン認証のときだけ効く。
    #
    # @param scope [String, Symbol] :read または :run
    def api_requires_scope(scope)
      self.api_required_scope = scope.to_s
    end
  end

  # このリクエストの Bearer 認証に使われたトークン（Cookie 認証なら nil）。
  # 課金・利用量記録（#145）がトークン単位で扱えるように公開している。
  attr_reader :current_api_token

  # 認証済みの人の所属マーケットプレイス。
  #
  # API は `fetch_community`（HTML ページ向け）を実行しないため、
  # `@current_community` が無い。出品の可視性や検索のスコープはここで解決する
  # （#145 の参照系、#144 の実行系）。
  #
  # @return [Community]
  def api_community
    @api_community ||= current_user.community
  end

  # Authorization: Bearer を解決する。ヘッダが無ければ何もしない。
  def authenticate_api_token!
    raw_token = bearer_token
    return if raw_token.blank?

    token = APIToken.authenticate(raw_token)
    return render_invalid_token(raw_token) unless token

    # 以降のフィルタ・アクションは通常のログイン済みリクエストと同じ形で
    # 動かす（current_person / current_user の両方を同じ person に揃える）。
    sign_in(token.person, store: false)
    @current_user = token.person
    @current_api_token = token

    touch_last_used_at(token)
  end

  # 認証済みか。認証方法（Bearer / Cookie）に依らない共通の入口。
  def ensure_authenticated
    return if current_user

    render json: { error: "ログインが必要です" }, status: :unauthorized
  end

  # トークン認証のときだけ scope を検査する。
  def ensure_api_scope
    return if current_api_token.nil?
    return if current_api_token.allows?(api_required_scope)

    Rails.logger.info(
      "[api_token] scope 不足 token_id=#{current_api_token.id} " \
      "required=#{api_required_scope} granted=#{current_api_token.scope_list.join(',')}"
    )
    render json: { error: "insufficient_scope" }, status: :forbidden
  end

  private

  # Authorization ヘッダの生トークン（`Bearer <token>` / `Token <token>`）。
  def bearer_token
    return @bearer_token if defined?(@bearer_token)

    token = nil
    authenticate_with_http_token { |raw, _options| token = raw }
    @bearer_token = token
  end

  # 401 の理由（未登録 / 失効 / 期限切れ）はレスポンスに含めず、ログにだけ残す。
  def render_invalid_token(raw_token)
    Rails.logger.info("[api_token] 認証失敗 reason=#{invalid_token_reason(raw_token)}")
    render json: { error: "invalid_token" }, status: :unauthorized
  end

  # @return [String] unknown / revoked / expired / inactive
  def invalid_token_reason(raw_token)
    record = APIToken.find_by(token_digest: APIToken.digest(raw_token))
    return "unknown" if record.nil?
    return "revoked" if record.revoked?

    record.expired? ? "expired" : "inactive"
  end

  # 前回の更新から LAST_USED_AT_INTERVAL 以上経ったときだけ書き換える。
  def touch_last_used_at(token)
    last_used_at = token.last_used_at
    return if last_used_at.present? && last_used_at > LAST_USED_AT_INTERVAL.ago

    token.touch_last_used!
  end
end
