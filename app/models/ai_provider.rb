# frozen_string_literal: true
# == Schema Information
#
# Table name: ai_providers
#
#  id                :integer          not null, primary key
#  name              :string(255)      not null
#  slug              :string(255)      not null
#  api_key_encrypted :string(255)
#  base_url          :string(255)
#  config            :json
#  is_active         :boolean          default(TRUE)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_ai_providers_on_slug  (slug) UNIQUE
#

class AiProvider < ApplicationRecord
  has_many :ai_models, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(is_active: true) }

  # Decrypts and returns the stored API key.
  #
  # @return [String, nil] the plaintext API key, or nil if not set
  def api_key
    return nil if api_key_encrypted.blank?

    EncryptionService.decrypt(api_key_encrypted)
  end

  # Encrypts and stores the API key.
  #
  # @param key [String] the plaintext API key
  def api_key=(key)
    self.api_key_encrypted = key.present? ? EncryptionService.encrypt(key) : nil
  end
end
