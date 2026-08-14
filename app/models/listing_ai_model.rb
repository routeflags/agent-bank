# frozen_string_literal: true
# == Schema Information
#
# Table name: listing_ai_models
#
#  id          :integer          not null, primary key
#  listing_id  :integer          not null
#  ai_model_id :integer          not null
#  is_default  :boolean          default(FALSE)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_listing_ai_models_on_ai_model_id                 (ai_model_id)
#  index_listing_ai_models_on_listing_id_and_ai_model_id  (listing_id,ai_model_id) UNIQUE
#  index_listing_ai_models_on_listing_id_default_unique   (listing_id) UNIQUE
#

class ListingAiModel < ApplicationRecord
  belongs_to :listing
  belongs_to :ai_model

  # Ensures only one default model per listing.
  before_save :ensure_single_default

  scope :defaults, -> { where(is_default: true) }

  private

  # When marking this record as default, unset any other defaults
  # for the same listing to maintain a single default invariant.
  def ensure_single_default
    return unless is_default?

    ListingAiModel
      .where(listing_id: listing_id, is_default: true)
      .where.not(id: id)
      .update_all(is_default: false)
  end
end
