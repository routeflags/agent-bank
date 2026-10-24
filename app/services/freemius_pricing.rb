# frozen_string_literal: true

require "bigdecimal"
require "json"

# JPY → USD conversion for Freemius billing (Issue #43 follow-up).
#
# Freemius only supports USD/EUR/GBP, so JPY listing prices
# (`listing.price_cents`, in yen) are converted to USD cents for charging.
# The conversion rate is operator-owned via the environment variable
# `FREEMIUS_JPY_USD_RATE` (USD per 1 JPY, e.g. `0.0067`). There is no
# default rate: when the variable is missing or invalid, conversion is
# unavailable and production billing must refuse with
# 503 `payment_unconfigured` instead of silently charging a guessed rate.
#
# This module is the single entry point for the conversion (#46 reuses it).
# Freemius plan prices themselves are fixed in USD on the Dashboard; the
# converted value is used to choose a plan and to show the buyer an
# estimate. The hosted checkout page always shows the true charge.
#
# Usage:
#   FreemiusPricing.configured? # => true when the rate env var is valid
#   FreemiusPricing.usd_cents_for_jpy(3000) # => 2010 (with rate 0.0067)
module FreemiusPricing
  class RateMissingError < StandardError; end

  RATE_ENV_VAR = "FREEMIUS_JPY_USD_RATE"
  PLAN_PRICE_MAP_ENV_VAR = "FREEMIUS_PLAN_PRICE_MAP"
  TOLERANCE_ENV_VAR = "FREEMIUS_PRICE_TOLERANCE_PCT"

  CURRENCY = "usd"
  CENTS_PER_DOLLAR = 100
  DEFAULT_TOLERANCE_PCT = 20.0

  class << self
    # USD per 1 JPY (e.g. 0.0067), or nil when missing/invalid.
    #
    # @return [Float, nil]
    def rate
      raw = ENV[RATE_ENV_VAR].to_s.strip
      return nil if raw.empty?

      parsed = Float(raw)
      return nil unless parsed.finite? && parsed.positive?

      parsed
    rescue ArgumentError, TypeError
      nil
    end

    # Whether a usable conversion rate is configured.
    #
    # @return [Boolean]
    def configured?
      !rate.nil?
    end

    # Converts a JPY yen amount to USD cents, rounding UP to the smallest
    # currency unit (1 cent = 0.01 USD).
    #
    # Formula: usd_cents = ceil(yen * rate * 100), computed with BigDecimal
    # to avoid binary float error. Zero/negative input maps to 0 (free
    # listings are handled upstream with 422; this never raises for them).
    #
    # @param yen_cents [Integer] JPY amount in yen (e.g. listing.price_cents)
    # @return [Integer] USD amount in cents
    # @raise [RateMissingError] when no valid rate is configured
    def usd_cents_for_jpy(yen_cents)
      current = rate
      raise RateMissingError, "#{RATE_ENV_VAR} is not configured" if current.nil?

      yen = yen_cents.to_i
      return 0 if yen <= 0

      (BigDecimal(yen.to_s) * BigDecimal(current.to_s) * CENTS_PER_DOLLAR).ceil.to_i
    end

    # Full amount breakdown for API responses and display.
    #
    # @param yen_cents [Integer] JPY amount in yen
    # @return [Hash] { amount_jpy:, amount_usd_cents:, currency:, fx_rate: }
    # @raise [RateMissingError] when no valid rate is configured
    def amounts_for_jpy(yen_cents)
      current = rate
      raise RateMissingError, "#{RATE_ENV_VAR} is not configured" if current.nil?

      {
        amount_jpy: yen_cents.to_i,
        amount_usd_cents: usd_cents_for_jpy(yen_cents),
        currency: CURRENCY,
        fx_rate: current
      }
    end

    # Formats USD cents as dollars (e.g. 2010 -> "20.10").
    #
    # @param usd_cents [Integer]
    # @return [String]
    def format_usd(usd_cents)
      format("%.2f", usd_cents.to_i / CENTS_PER_DOLLAR.to_f)
    end

    # Optional operator-maintained map of Freemius plan price in USD cents:
    # `{ "<plan_id>": <usd_cents> }`. Absent/broken JSON means "no check".
    #
    # @return [Hash]
    def plan_price_map
      raw = ENV[PLAN_PRICE_MAP_ENV_VAR].to_s.strip
      return {} if raw.empty?

      parsed = JSON.parse(raw)
      return {} unless parsed.is_a?(Hash)

      parsed.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value.to_i
      end
    rescue JSON::ParserError
      {}
    end

    # Price tolerance in percent for the plan-price drift check.
    #
    # @return [Float]
    def tolerance_pct
      raw = ENV[TOLERANCE_ENV_VAR].to_s.strip
      return DEFAULT_TOLERANCE_PCT if raw.empty?

      parsed = Float(raw)
      return DEFAULT_TOLERANCE_PCT unless parsed.finite? && parsed.positive?

      parsed
    rescue ArgumentError, TypeError
      DEFAULT_TOLERANCE_PCT
    end

    # Whether a converted amount is within tolerance of a plan price.
    #
    # @param converted_cents [Integer] converted USD cents
    # @param plan_price_cents [Integer] Dashboard plan price in USD cents
    # @param pct [Float] allowed relative deviation in percent
    # @return [Boolean]
    def within_tolerance?(converted_cents, plan_price_cents, pct = tolerance_pct)
      plan = plan_price_cents.to_i
      return true if plan <= 0

      deviation = ((converted_cents.to_i - plan).abs.to_f / plan) * 100.0
      deviation <= pct.to_f
    end

    # Compares a converted amount against the known Dashboard plan price.
    # Logs a warning on drift but never blocks: the hosted checkout page
    # shows the true charge, so availability is preferred over strictness.
    #
    # @param plan_id [String, Integer, nil]
    # @param converted_cents [Integer]
    # @return [Symbol] :ok, :unknown (no map entry), or :mismatch
    def check_plan_price(plan_id, converted_cents)
      expected = plan_price_map[plan_id.to_s]
      return :unknown if expected.nil?

      if within_tolerance?(converted_cents, expected)
        :ok
      else
        Rails.logger.warn(
          "[FreemiusPricing] plan price drift: plan=#{plan_id} " \
          "converted=#{converted_cents}c expected=#{expected}c " \
          "tolerance=#{tolerance_pct}%"
        )
        :mismatch
      end
    end
  end
end
