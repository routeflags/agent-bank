# frozen_string_literal: true

# == Schema Information
#
# Table name: usage_records
#
#  id                         :bigint           not null, primary key
#  ai_model_id                :bigint
#  user_plan_subscription_id  :bigint
#  input_tokens               :integer          default(0)
#  output_tokens              :integer          default(0)
#  total_tokens               :integer          default(0)
#  cost_cents                 :integer          default(0)
#  charge_cents               :integer          default(0)
#  billing_model              :string
#  currency                   :string           default("USD")
#  metadata                   :json
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
# Indexes
#
#  index_usage_records_on_user_plan_subscription_id_and_created_at  (user_plan_subscription_id,created_at)
#  index_usage_records_on_ai_model_id                               (ai_model_id)
#

class UsageRecord < ApplicationRecord
  belongs_to :ai_model, optional: true
  belongs_to :user_plan_subscription, optional: true

  before_create :calculate_totals

  private

  # Compute derived fields from token counts and model pricing.
  def calculate_totals
    self.total_tokens = (input_tokens || 0) + (output_tokens || 0)
    self.cost_cents = calculate_cost_cents
  end

  # Convert ai_model cost_per_1k rates into an integer cent value.
  # Uses BigDecimal to avoid floating-point precision issues with monetary values.
  #
  # @return [Integer] cost in cents
  def calculate_cost_cents
    return 0 unless ai_model&.cost_per_1k_input && ai_model&.cost_per_1k_output

    input_cost  = BigDecimal(input_tokens.to_s) / 1000 * BigDecimal(ai_model.cost_per_1k_input.to_s)
    output_cost = BigDecimal(output_tokens.to_s) / 1000 * BigDecimal(ai_model.cost_per_1k_output.to_s)
    ((input_cost + output_cost) * 100).to_i
  end
end
