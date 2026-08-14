# frozen_string_literal: true

# == Schema Information
#
# Table name: chat_sessions
#
#  id            :bigint           not null, primary key
#  person_id     :string(22)       not null
#  listing_id    :integer          not null
#  status        :string           default("active"), not null
#  billing_model :string
#  started_at    :datetime
#  ended_at      :datetime
#  total_tokens  :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_chat_sessions_on_listing_id_and_person_id  (listing_id,person_id)
#  index_chat_sessions_on_person_id_and_status      (person_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (listing_id => listings.id)
#

class ChatSession < ApplicationRecord
  STATUSES = %w[active closed].freeze

  belongs_to :listing
  # people.id is varchar(22) without UNIQUE, so DB-level FK is skipped.
  # Referential integrity is enforced at the application level.
  belongs_to :person
  has_many :chat_messages, dependent: :destroy

  validates :person_id, presence: true
  validates :listing_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
  scope :for_person, ->(person) { where(person_id: person.id) }

  # Mark this session as closed and record the end time.
  def close!
    update!(status: "closed", ended_at: Time.current)
  end
end
