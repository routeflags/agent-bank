# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Thin HTTP client for the Freemius REST API.
#
# Freemius acts as the Merchant of Record: checkout sessions are created
# here, and payment/subscription completion is delivered back via webhooks
# (see FreemiusWebhooksController). This client only performs outbound
# API calls with Bearer token authentication.
#
# Reference: https://freemius.com/help/api/
#
# Usage:
#   client = FreemiusClient.new
#   session = client.create_checkout(amount_cents: 3000, currency: "USD",
#                                    user_id: "abc", wallet_id: 1)
#   # => { "checkout_url" => "https://...", "payment_id" => "..." }
module FreemiusClient
  class ApiError < StandardError; end

  DEFAULT_BASE_URL = "https://api.freemius.com/v1"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30

  class << self
    # Creates a checkout session for a wallet top-up.
    #
    # @param amount_cents [Integer] charge amount in cents
    # @param currency [String] ISO currency code (e.g. "USD")
    # @param user_id [String] local person ID (stored in metadata for webhook matching)
    # @param wallet_id [Integer] local wallet ID (stored in metadata)
    # @param success_url [String, nil] redirect target after successful payment
    # @param cancel_url [String, nil] redirect target after cancellation
    # @return [Hash] { "checkout_url" => String, "payment_id" => String }
    # @raise [ApiError] when credentials are missing or the API errors
    def create_checkout(amount_cents:, currency:, user_id:, wallet_id:,
                        success_url: nil, cancel_url: nil)
      body = {
        amount_cents: amount_cents,
        currency: currency,
        metadata: {
          user_id: user_id,
          wallet_id: wallet_id,
          type: "wallet_topup"
        }
      }
      body[:success_url] = success_url if success_url
      body[:cancel_url] = cancel_url if cancel_url

      post("/checkouts", body)
    end

    # Creates a checkout session for a persona purchase (one listing unit).
    #
    # Separate from the wallet top-up checkout: metadata carries
    # type: "persona_purchase" plus listing_id / user_id so the webhook
    # (FreemiusWebhooksController) can grant the purchase entitlement
    # (UserPlanSubscriptionService.create_for) after server-side verification.
    #
    # @param amount_cents [Integer] listing price in cents (server-side value)
    # @param currency [String] ISO currency code (e.g. "JPY")
    # @param user_id [String] local person ID (stored in metadata for webhook matching)
    # @param listing_id [Integer] local listing ID (stored in metadata)
    # @param success_url [String, nil] redirect target after successful payment
    # @param cancel_url [String, nil] redirect target after cancellation
    # @return [Hash] { "checkout_url" => String, "payment_id" => String }
    # @raise [ApiError] when credentials are missing or the API errors
    def create_persona_purchase_checkout(amount_cents:, currency:, user_id:, listing_id:,
                                         success_url: nil, cancel_url: nil)
      body = {
        amount_cents: amount_cents,
        currency: currency,
        metadata: {
          type: "persona_purchase",
          user_id: user_id,
          listing_id: listing_id
        }
      }
      body[:success_url] = success_url if success_url
      body[:cancel_url] = cancel_url if cancel_url

      post("/checkouts", body)
    end

    # Retrieves a payment by its Freemius payment ID.
    #
    # @param payment_id [String]
    # @return [Hash] payment object
    def get_payment(payment_id)
      get("/payments/#{payment_id}")
    end

    # Retrieves a subscription by its Freemius subscription ID.
    #
    # @param subscription_id [String]
    # @return [Hash] subscription object
    def get_subscription(subscription_id)
      get("/subscriptions/#{subscription_id}")
    end

    # Whether Freemius credentials are configured.
    #
    # @return [Boolean]
    def configured?
      api_key.present?
    end

    private

    def api_key
      ENV["FREEMIUS_API_KEY"]
    end

    def base_url
      ENV.fetch("FREEMIUS_API_BASE_URL", DEFAULT_BASE_URL)
    end

    def post(path, body)
      request(:post, path, body)
    end

    def get(path)
      request(:get, path, nil)
    end

    def request(method, path, body)
      raise ApiError, "FREEMIUS_API_KEY is not configured" unless configured?

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
