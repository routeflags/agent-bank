# frozen_string_literal: true

# == Schema Information
#
# Table name: ai_models
#
#  id                  :bigint           not null, primary key
#  ai_provider_id      :bigint           not null
#  name                :string           not null
#  slug                :string           not null
#  model_id            :string           not null
#  max_tokens          :integer          default(4096)
#  context_window      :integer
#  cost_per_1k_input   :decimal(8, 6)
#  cost_per_1k_output  :decimal(8, 6)
#  supports_streaming  :boolean          default(TRUE)
#  supports_vision     :boolean          default(FALSE)
#  supports_tools      :boolean          default(FALSE)
#  is_active           :boolean          default(TRUE)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_ai_models_on_ai_provider_id_and_model_id  (ai_provider_id,model_id) UNIQUE
#  index_ai_models_on_ai_provider_id_and_slug      (ai_provider_id,slug) UNIQUE
#  index_ai_models_on_ai_provider_id               (ai_provider_id)
#

class AiModel < ApplicationRecord
  belongs_to :ai_provider
  has_many :listing_ai_models, dependent: :destroy
  has_many :listings, through: :listing_ai_models

  validates :name, presence: true
  validates :slug, presence: true
  validates :model_id, presence: true
  validates :slug, uniqueness: { scope: :ai_provider_id }
  validates :model_id, uniqueness: { scope: :ai_provider_id }

  scope :active, -> { where(is_active: true) }

  # Estimates the cost for a given number of tokens.
  #
  # @param input_tokens [Integer]
  # @param output_tokens [Integer]
  # @return [BigDecimal, nil] estimated cost, or nil if pricing not set
  def estimate_cost(input_tokens, output_tokens)
    return nil if cost_per_1k_input.nil? || cost_per_1k_output.nil?

    input_cost = (input_tokens / 1000.0) * cost_per_1k_input
    output_cost = (output_tokens / 1000.0) * cost_per_1k_output
    input_cost + output_cost
  end
end
