# frozen_string_literal: true

# Validates FREEMIUS_TOPUP_PLAN_MAP at boot (Issue #46).
# Logs misconfiguration instead of raising so a bad map never prevents boot;
# requests fail closed via FreemiusTopupPlans.configured? (503 payment_unconfigured).
Rails.application.config.after_initialize do
  begin
    errors = FreemiusTopupPlans.validation_errors
    if errors.empty?
      if FreemiusTopupPlans.plans.any?
        Rails.logger.info("[FreemiusTopupPlans] Configured denominations: #{FreemiusTopupPlans.plans.inspect}")
      else
        Rails.logger.info("[FreemiusTopupPlans] Not configured (no fixed prepaid plans)")
      end
    else
      Rails.logger.warn("[FreemiusTopupPlans] Misconfigured: #{errors.join('; ')}")
    end
  rescue StandardError => e
    Rails.logger.warn("[FreemiusTopupPlans] Validation failed: #{e.message}")
  end
end
