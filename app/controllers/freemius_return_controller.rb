# frozen_string_literal: true

require "openssl"
require "uri"

# Freemius hosted checkout return destination (Issue #43 completion).
#
# Freemius hosted checkout has two return paths:
#   * Back button (cancel): per-checkout `cancel_url` query param. The server
#     attaches the listing page (persona) or the site root (wallet) to every
#     hosted URL, so "cancel returns to the original page" holds.
#   * Success redirect: global per-plan setting (Dashboard Plans →
#     Customization → Redirect Checkout to a custom URL). Freemius appends
#     `user_id/plan_id/email/payment_id/license_id/amount/signature` etc.
#     `signature` = HMAC-SHA256(clean_url, PRODUCT_SECRET_KEY) where clean_url
#     is the absolute URL minus `&signature=...`.
#     (https://freemius.com/help/documentation/checkout/integration/hosted-checkout/)
#
# This endpoint renders the success page directly (no redirect: redirecting
# would break the signature chain per the Freemius warning). The page is a
# generic completion notice: wallet top-up is not tied to a listing
# (Issue #51 — there is no per-persona purchase).
#
# Route: GET /freemius/return (see config/routes.rb, next to the webhook).
class FreemiusReturnController < ApplicationController
  skip_before_action :verify_authenticity_token,
                     :fetch_logged_in_user,
                     :fetch_community,
                     :perform_redirect,
                     :fetch_community_membership,
                     :check_http_auth,
                     :cannot_access_without_confirmation,
                     :ensure_consent_given,
                     :ensure_user_belongs_to_community

  layout false

  # The return page is reachable without a community context (skipped
  # above), but when the buyer returns in the same browser their Devise
  # session is still present. Expose it read-only so the view can offer
  # a "back to mypage" link (Issue #58). Never redirects or 401s here.
  before_action :fetch_return_viewer, only: [:success]

  # GET /freemius/return
  #
  # Always 200 (500 にしない): invalid signature shows a warning, valid shows
  # completion. Webhook (signed server-to-server) grants the entitlement;
  # this page only informs (never grants).
  def success
    # `locale` は Sharetribe の locale リダイレクトと衝突するため `lang` を使う。
    # Dashboard の redirect URL に `?lang=ja` を含めておくと日本語表示になる
    #（署名対象に含まれるため改ざんできない）。
    I18n.locale = params[:lang].to_sym if %w[ja en].include?(params[:lang].to_s)
    @plan_id = params[:plan_id].to_s.strip.presence
    @payment_id = params[:payment_id].to_s.strip.presence
    @verification = verify_redirect_signature
    @listing = nil
    unless @verification[:valid]
      Rails.logger.warn("[FreemiusReturn] Invalid redirect signature")
    end

    render :success
  end

  private

  # Best-effort viewer lookup for the mypage link. Devise session only;
  # no community load, no redirect, no failure modes (always 200).
  def fetch_return_viewer
    @current_user = current_person if person_signed_in?
  rescue StandardError
    @current_user = nil
  end

  # Verifies the Freemius success-redirect `signature` query param.
  # Algorithm: HMAC-SHA256(clean_url, PRODUCT_SECRET_KEY) where clean_url is
  # the absolute URL without the trailing `&signature=...` (or `?signature=`).
  #
  # @return [Hash] { valid: Boolean, reason: String/nil }
  def verify_redirect_signature
    secret = FreemiusClient.webhook_secret
    return { valid: false, reason: "secret_unconfigured" } if secret.blank?

    given = params[:signature].to_s.strip
    return { valid: false, reason: "signature_missing" } if given.empty?

    clean = clean_url_without_signature(request.original_url)
    return { valid: false, reason: "unverifiable_url" } if clean.nil?

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, clean)
    valid = ActiveSupport::SecurityUtils.secure_compare(expected, given)
    { valid: valid, reason: valid ? nil : "signature_mismatch" }
  rescue StandardError => e
    { valid: false, reason: e.message.to_s[0, 120] }
  end

  # Removes the `signature` query param, preserving the order of the rest.
  #
  # @param url [String] absolute URL
  # @return [String, nil] clean URL or nil when unparseable
  def clean_url_without_signature(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.scheme && uri.host

    pairs = URI.decode_www_form(uri.query.to_s).reject { |k, _| k == "signature" }
    uri.query = pairs.empty? ? nil : URI.encode_www_form(pairs)
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end


end
