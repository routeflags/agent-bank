# frozen_string_literal: true

# Reads billing configuration from config/billing.yml with fallback defaults.
# All monetary values are in cents (integer).
#
# Usage:
#   BillingConfig.base_price_cents(:subscription)
#   BillingConfig.per_token_price_cents(:pay_per_use)
#   BillingConfig.auto_recharge_threshold_cents
#
module BillingConfig
  CONFIG_PATH = Rails.root.join("config", "billing.yml")

  class << self
    # --- Subscription (Model 1) ---

    def base_price_cents(model_type = :subscription)
      dig_config(model_type, :base_price_cents) || 1000
    end

    def included_tokens(model_type = :subscription)
      dig_config(model_type, :included_tokens) || 100_000
    end

    def per_token_price_cents(model_type = :subscription)
      dig_config(model_type, :per_token_price_cents) || default_per_token_price(model_type)
    end

    # --- Pay-per-use (Model 2) ---

    def pay_per_use_per_token_price_cents
      dig_config(:pay_per_use, :per_token_price_cents) || 3
    end

    # --- Auto-recharge (Model 3) ---

    def auto_recharge_threshold_cents
      dig_config(:subscription_with_overage, :auto_recharge_threshold_cents) || 500
    end

    def auto_recharge_amount_cents
      dig_config(:subscription_with_overage, :auto_recharge_amount_cents) || 2000
    end

    def max_monthly_charge_cents
      dig_config(:subscription_with_overage, :max_monthly_charge_cents) || 10_000
    end

    # --- Shared ---

    def currency
      dig_config(:currency) || "USD"
    end

    def unit_type
      dig_config(:unit_type) || "tokens"
    end

    private

    # Safely read from config/billing.yml, returning nil on any failure.
    def config
      @config ||= load_config
    end

    def load_config
      return {} unless File.exist?(CONFIG_PATH)

      YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [Symbol])
          .dig("billing") || {}
    rescue StandardError => e
      Rails.logger.warn("[BillingConfig] Failed to load #{CONFIG_PATH}: #{e.message}")
      {}
    end

    # Navigate nested hash; returns nil if any key is missing.
    def dig_config(*keys)
      config.dig(*keys)
    end

    def default_per_token_price(model_type)
      case model_type.to_sym
      when :subscription, :subscription_with_overage
        2
      when :pay_per_use
        3
      else
        2
      end
    end
  end
end
