# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Thin HTTP client for the Freemius REST API (product scope).
#
# Freemius acts as the Merchant of Record. Checkout is hosted and plan-based:
#   https://checkout.freemius.com/product/{product_id}/plan/{plan_id}/
# There is no server API to create a checkout with an arbitrary amount
# (see Issue #43 and documents/guides/freemius_production_setup.md).
# This client therefore:
#   * builds hosted checkout URLs locally (no network call), and
#   * performs outbound product-scoped API calls with Bearer authentication
#     for server-side verification (payments / subscriptions).
# Completion is delivered back via webhooks (see FreemiusWebhooksController).
#
# Reference: https://freemius.com/help/api/ (Bearer Token Authentication,
#   product scope: GET /products/{product_id}/payments/{payment_id}.json)
# OpenAPI: https://api.freemius.com/v1/openapi.json (112 paths, no /checkouts)
# Checkout: https://freemius.com/help/documentation/checkout/integration/hosted-checkout/
# Webhooks: https://freemius.com/help/documentation/marketing-automation/events-webhooks/
#
# Usage:
#   FreemiusClient.configured? # => product_id + Bearer both present
#   url = FreemiusClient.build_hosted_checkout_url(plan_id: "5678", user_email: "a@x")
#   payment = FreemiusClient.get_payment("9876")
module FreemiusClient
  class ApiError < StandardError; end

  DEFAULT_BASE_URL = "https://api.freemius.com/v1"
  HOSTED_CHECKOUT_BASE_URL = "https://checkout.freemius.com"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30

  class << self
    # Builds a hosted checkout URL for a plan (no network call).
    #
    # Freemius Checkout is plan-based; an arbitrary amount_cents cannot be
    # specified. The caller passes a fixed denomination plan_id (see
    # FreemiusTopupPlans for wallet top-up). Amounts/currency are defined
    # in the Dashboard Plans/Pricing (usd|eur|gbp only).
    #
    # @param plan_id [String, Integer] Freemius plan ID (required)
    # @param user_email [String, nil] prefill + webhook correlation hint
    # @param cancel_url [String, nil] hosted checkout back-button target
    # @param extra [Hash] additional query params (coupon, title, etc.)
    # @return [String] hosted checkout URL
    # @raise [ApiError] when product_id is missing or plan_id is blank
    def build_hosted_checkout_url(plan_id:, user_email: nil, cancel_url: nil, extra: {})
      pid = product_id
      raise ApiError, "FREEMIUS_PRODUCT_ID is not configured" if pid.blank?
      raise ApiError, "plan_id is required for Freemius hosted checkout" if plan_id.to_s.strip.empty?

      base = "#{HOSTED_CHECKOUT_BASE_URL}/product/#{encode(pid)}/plan/#{encode(plan_id.to_s.strip)}/"
      params = {}
      params.merge!(extra.transform_keys(&:to_s)) if extra
      params["user_email"] = user_email.to_s.strip if user_email.to_s.strip.present?
      params["readonly_user"] = "true" if user_email.to_s.strip.present?
      params["cancel_url"] = cancel_url.to_s.strip if cancel_url.to_s.strip.present?
      return base if params.empty?

      "#{base}?#{URI.encode_www_form(params)}"
    end

    # Retrieves a payment by its Freemius payment ID (product scope).
    #
    # Real path: GET /products/{product_id}/payments/{payment_id}.json
    #
    # @param payment_id [String]
    # @return [Hash] payment object (gross: Float, currency:, id:, ...)
    def get_payment(payment_id)
      get(product_path("payments/#{encode(payment_id.to_s)}"))
    end

    # Retrieves a user (buyer) by their Freemius user ID (product scope).
    #
    # Real path: GET /products/{product_id}/users/{user_id}.json
    # Useful to resolve the buyer's email from a payment when the webhook
    # payload is not available (e.g. manual debugging).
    #
    # @param user_id [String, Integer]
    # @return [Hash] user object (email, first, last, ...)
    def get_user(user_id)
      get(product_path("users/#{encode(user_id.to_s)}"))
    end

    # Retrieves a subscription by its Freemius subscription ID (product scope).
    #
    # Real path: GET /products/{product_id}/subscriptions/{subscription_id}.json
    #
    # @param subscription_id [String]
    # @return [Hash] subscription object
    def get_subscription(subscription_id)
      get(product_path("subscriptions/#{encode(subscription_id.to_s)}"))
    end

    # Converts a Freemius payment hash to cents.
    # Real schema uses `gross` (Float, tax-excluded). Legacy stubs/tests may
    # use `amount_cents` / `amount` (cents). This helper accepts both.
    #
    # @param payment [Hash]
    # @return [Integer] amount in cents (0 when unresolvable)
    def payment_amount_cents(payment)
      return 0 unless payment.is_a?(Hash)

      cents = payment["amount_cents"] || payment[:amount_cents] ||
              payment["amount"] || payment[:amount]
      return cents.to_i if cents.to_i.positive?

      gross = payment["gross"] || payment[:gross]
      return 0 if gross.nil? || gross.to_f <= 0

      (gross.to_f * 100).round
    end

    # Whether Freemius server credentials are configured.
    # Requires the numeric product_id AND the Bearer token.
    #
    # @return [Boolean]
    def configured?
      product_id.present? && bearer_token.present?
    end

    # Webhook HMAC secret: PRODUCT_SECRET_KEY (preferred) or legacy fallback.
    #
    # @return [String, nil]
    def webhook_secret
      secret = ENV["PRODUCT_SECRET_KEY"].to_s.strip
      return secret if secret.present?

      legacy = ENV["FREEMIUS_WEBHOOK_SECRET"].to_s.strip
      legacy.presence
    end

    # Numeric Freemius product ID (Dashboard → product Settings → API & Keys).
    #
    # `.env` の命名を他の Freemius キー（`PRODUCT_PUBLIC_KEY` /
    # `PRODUCT_SECRET_KEY`）に揃えて `PRODUCT_ID` を正とする。旧名
    # `FREEMIUS_PRODUCT_ID` は後方互換で読む。
    #
    # @return [String, nil]
    def product_id
      pid = ENV["PRODUCT_ID"].to_s.strip
      return pid if pid.present?

      legacy = ENV["FREEMIUS_PRODUCT_ID"].to_s.strip
      legacy.presence
    end

    private

    def bearer_token
      token = ENV["API_BEARER_AUTHORIZATION_TOKEN"].to_s.strip
      return token if token.present?

      legacy = ENV["FREEMIUS_API_KEY"].to_s.strip
      legacy.presence
    end

    # Kept for backward compatibility with callers/tests referencing api_key.
    def api_key
      bearer_token
    end

    def base_url
      ENV.fetch("FREEMIUS_API_BASE_URL", DEFAULT_BASE_URL)
    end

    def product_path(rest)
      suffix = rest.end_with?(".json") ? rest : "#{rest}.json"
      "/products/#{encode(product_id)}/#{suffix}"
    end

    def encode(part)
      URI.encode_www_form_component(part.to_s)
    end

    def get(path)
      request(:get, path, nil)
    end

    def request(method, path, body)
      unless configured?
        raise ApiError, "Freemius is not configured (FREEMIUS_PRODUCT_ID and API_BEARER_AUTHORIZATION_TOKEN are required)"
      end

      uri = URI.parse("#{base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      req = method == :post ? Net::HTTP::Post.new(uri.request_uri) : Net::HTTP::Get.new(uri.request_uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json if body

      response = http.request(req)
      parsed = parse_body(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError, "Freemius API error (#{response.code}): #{parsed['error'] || response.body.to_s[0, 200]}"
      end

      parsed
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ApiError, "Freemius API timeout: #{e.message}"
    rescue SocketError, SystemCallError => e
      raise ApiError, "Freemius API connection error: #{e.message}"
    end

    def parse_body(raw)
      return {} if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      { "raw" => raw.to_s[0, 500] }
    end
  end
end
