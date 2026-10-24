# frozen_string_literal: true

require "json"

# Fixed-amount prepaid plans for wallet top-up (Issue #46).
#
# Freemius cannot charge an arbitrary amount (plan-based only), so wallet
# top-up uses Dashboard "denomination" plans. This module is the single
# source of truth that resolves `plan_id -> credit (yen)` from
# `FREEMIUS_TOPUP_PLAN_MAP` (JSON: `{ "<plan_id>": <credit_yen> }`).
#
# Example: `{ "5678": 1000, "5679": 3000 }` means plan 5678 credits
# 1,000 yen and plan 5679 credits 3,000 yen. The hosted checkout page
# shows the true USD charge; the yen value here is the wallet credit.
#
# Currency note: `balance_cents` is yen-denominated in the wallet UI
# (100 = 1 yen x 100? No: 1 yen = 1 cent unit, e.g. 3000 = 3,000 yen).
# USD display is an estimate via `FreemiusPricing` (the sole JPY->USD
# entry point). This module never converts by itself; it delegates to
# `FreemiusPricing` so no new conversion logic is introduced.
#
# Validation (missing / duplicate / invalid) runs on every reference
# (fail-closed): `configured?` is false when the map is absent or invalid,
# and `validation_errors` explains why. Overlap with persona plans
# (`FREEMIUS_PLAN_MAP` values / `FREEMIUS_PLAN_ID`) is an error because
# the webhook dispatches persona first — an overlapping plan would never
# credit the wallet and would mislead the buyer.
#
# Usage:
#   FreemiusTopupPlans.configured? # => true when map is present and valid
#   FreemiusTopupPlans.credit_for_plan("5678") # => 1000 (yen) or nil
#   FreemiusTopupPlans.available_denominations # => [{ plan_id:, ... }]
module FreemiusTopupPlans
  TOPUP_PLAN_MAP_ENV_VAR = "FREEMIUS_TOPUP_PLAN_MAP"

  MIN_CREDIT_YEN = 100
  MAX_CREDIT_YEN = 100_000

  class << self
    # Whether fixed prepaid top-up is usable (map present and valid).
    #
    # @return [Boolean]
    def configured?
      validation_errors.empty? && plans_raw_valid_present?
    end

    # Parsed and validated map: `{ "<plan_id>" => <credit_yen Integer> }`.
    # Returns {} when missing or invalid (see `validation_errors`).
    #
    # @return [Hash]
    def plans
      parsed = parse_map
      return {} unless parsed.is_a?(Hash) && !parsed.empty?

      validated = {}
      parsed.each do |key, value|
        pid = key.to_s.strip
        credit = integer_credit(value)
        next if pid.empty? || credit.nil?
        next unless credit.between?(MIN_CREDIT_YEN, MAX_CREDIT_YEN)

        validated[pid] = credit
      end
      # Raw duplicate keys are caught by validation; parsed hash keeps last.
      # Only return the map when fully valid (no partial credit).
      return {} unless validation_errors.empty?

      validated
    end

    # Credit (yen) for a plan_id, or nil when unknown/invalid.
    # Exact string match only — no prefix matching (`fs` IDs are Freemius
    # payment IDs, not plan IDs; plan_ids are compared as exact strings so
    # "1" never matches "10").
    #
    # @param plan_id [String, Integer, nil]
    # @return [Integer, nil]
    def credit_for_plan(plan_id)
      pid = plan_id.to_s.strip
      return nil if pid.empty?

      plans[pid]
    end

    # Denominations for `GET /api/v1/wallet_topup/status`.
    # Each entry: `{ plan_id:, credit_jpy:, estimated_usd_cents:, currency:,
    #   fx_rate:, plan_price_usd_cents: (or nil) }`.
    # Returns [] when the rate or the map is unconfigured (fail-closed).
    #
    # @return [Array<Hash>]
    def available_denominations
      return [] unless configured?
      return [] unless FreemiusPricing.configured?

      rate = FreemiusPricing.rate
      price_map = FreemiusPricing.plan_price_map
      plans.sort_by { |_pid, credit| credit }.map do |pid, credit|
        {
          plan_id: pid,
          credit_jpy: credit,
          estimated_usd_cents: FreemiusPricing.usd_cents_for_jpy(credit),
          currency: FreemiusPricing::CURRENCY,
          fx_rate: rate,
          plan_price_usd_cents: price_map.key?(pid) ? price_map[pid].to_i : nil
        }
      end
    rescue FreemiusPricing::RateMissingError
      []
    end

    # Human-readable validation problems (empty when valid).
    # Covers: missing / broken JSON / non-object / empty / blank plan_id /
    # non-positive or out-of-range credit / raw duplicate keys /
    # overlap with persona plans.
    #
    # @return [Array<String>]
    def validation_errors
      errors = []
      raw = ENV[TOPUP_PLAN_MAP_ENV_VAR].to_s.strip
      if raw.empty?
        errors << "#{TOPUP_PLAN_MAP_ENV_VAR} is not configured"
        return errors
      end

      begin
        parsed = JSON.parse(raw)
      rescue JSON::ParserError => e
        errors << "#{TOPUP_PLAN_MAP_ENV_VAR} is broken JSON: #{e.message.to_s[0, 120]}"
        return errors
      end

      unless parsed.is_a?(Hash)
        errors << "#{TOPUP_PLAN_MAP_ENV_VAR} must be a JSON object"
        return errors
      end

      if parsed.empty?
        errors << "#{TOPUP_PLAN_MAP_ENV_VAR} is empty (no denominations)"
        return errors
      end

      # Duplicate raw keys: JSON.parse keeps the last, so scan the raw text.
      dups = duplicate_raw_keys(raw)
      dups.each do |k|
        errors << "#{TOPUP_PLAN_MAP_ENV_VAR} has duplicate plan_id: #{k.inspect}"
      end

      parsed.each do |key, value|
        pid = key.to_s.strip
        if pid.empty?
          errors << "#{TOPUP_PLAN_MAP_ENV_VAR} has a blank plan_id"
          next
        end
        credit = integer_credit(value)
        if credit.nil? || credit <= 0
          errors << "#{TOPUP_PLAN_MAP_ENV_VAR}[#{pid.inspect}] must be a positive integer (yen)"
        elsif !credit.between?(MIN_CREDIT_YEN, MAX_CREDIT_YEN)
          errors << "#{TOPUP_PLAN_MAP_ENV_VAR}[#{pid.inspect}] must be #{MIN_CREDIT_YEN}..#{MAX_CREDIT_YEN} yen"
        end
      end

      # Overlap with persona plans would misdispatch (persona wins).
      persona_ids = persona_plan_ids
      overlap = parsed.keys.map(&:to_s) & persona_ids
      overlap.each do |pid|
        errors << "#{TOPUP_PLAN_MAP_ENV_VAR}[#{pid.inspect}] overlaps a persona plan (webhook would grant entitlement, not wallet credit)"
      end

      errors
    end

    private

    def plans_raw_valid_present?
      !parse_map.empty?
    end

    def parse_map
      raw = ENV[TOPUP_PLAN_MAP_ENV_VAR].to_s.strip
      return {} if raw.empty?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Accepts Integer or integer-like String/Float ("3000", 3000.0).
    # Returns nil for non-numeric / fractional / non-positive text.
    def integer_credit(value)
      case value
      when Integer
        value
      when Float
        value == value.to_i ? value.to_i : nil
      when String
        s = value.strip
        return nil unless s.match?(/\A\d+\z/)

        s.to_i
      else
        nil
      end
    rescue StandardError
      nil
    end

    # Finds duplicate top-level JSON object keys by scanning the raw text.
    # Only string keys (`"123"`) are considered (plan_ids are strings).
    def duplicate_raw_keys(raw)
      keys = raw.scan(/"([^"\\]*)"\s*:/).flatten
      keys.tally.select { |_k, v| v > 1 }.keys
    end

    # Persona plan IDs from env (values of FREEMIUS_PLAN_MAP + FREEMIUS_PLAN_ID).
    def persona_plan_ids
      ids = []
      single = ENV["FREEMIUS_PLAN_ID"].to_s.strip
      ids << single unless single.empty?
      begin
        raw = ENV["FREEMIUS_PLAN_MAP"].to_s.strip
        unless raw.empty?
          parsed = JSON.parse(raw)
          ids.concat(parsed.values.map(&:to_s)) if parsed.is_a?(Hash)
        end
      rescue JSON::ParserError
        nil
      end
      ids.map(&:to_s).reject(&:empty?).uniq
    end
  end
end
