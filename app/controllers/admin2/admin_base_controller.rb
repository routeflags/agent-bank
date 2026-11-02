# This controller is parent for all controllers handling the admin area functions

class Admin2::AdminBaseController < ApplicationController
  layout 'layouts/admin'

  # 管理画面（/admin 配下）の保護（Issue #120）。
  #
  # `ADMIN_ALLOWED_IPS` が設定されているときだけ、送信元 IP の許可リストを強制する。
  # 未設定なら何もしない（開発・テストの挙動は従来どおり）。
  #
  # prepend にしているのは、未ログイン時のリダイレクト（ensure_is_admin）より
  # 先に 403 を返すため。
  prepend_before_action :restrict_admin_by_ip

  before_action :ensure_is_admin

  #Allow admin to access admin panel before email confirmation
  skip_before_action :cannot_access_without_confirmation

  def clp_enabled
    @current_plan.try(:[], :features).try(:[], :landing_page) &&
      CustomLandingPage::LandingPageStore.enabled?(@current_community&.id)
  end

  private

  # ENV の IP 許可リストに無い送信元には 403 を返す（ログイン状態に関係なく）。
  # ADMIN_ALLOWED_IPS が未設定なら何もしない。
  def restrict_admin_by_ip
    return unless AdminAccessControl.ip_restriction_enabled?
    return if AdminAccessControl.ip_allowed?(request.remote_ip)

    Rails.logger.warn(
      "[AdminAccessControl] /admin へのアクセスを IP で拒否しました: " \
      "remote_ip=#{request.remote_ip.inspect} path=#{request.path}"
    )
    head :forbidden
  end

  def setup_seo_service
    @seo_service = SeoService.new(@current_community, params)
  end

  def find_or_initialize_customizations_for_locale(locale)
    @current_community.community_customizations.find_by_locale(locale) || build_customization_with_defaults(locale)
  end

  def find_customizations
    @customizations = @current_community.community_customizations
                                        .where(locale: @current_community.locales)
  end

  def find_or_initialize_customizations(locales)
    locales.each_with_object({}) do |locale, customizations|
      customizations[locale] = find_or_initialize_customizations_for_locale(locale)
    end
  end
end
