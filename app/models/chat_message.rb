# frozen_string_literal: true

# == Schema Information
#
# Table name: chat_messages
#
#  id               :bigint           not null, primary key
#  chat_session_id  :bigint           not null
#  sender_type      :string
#  sender_id        :string(22)
#  content          :text
#  role             :string           default("user"), not null
#  seq              :integer          default(0), not null
#  input_tokens     :integer          default(0), not null
#  output_tokens    :integer          default(0), not null
#  metadata         :json
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_chat_messages_on_chat_session_id_and_created_at  (chat_session_id,created_at)
#  index_chat_messages_on_sender_type_and_sender_id       (sender_type,sender_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_session_id => chat_sessions.id)
#

class ChatMessage < ApplicationRecord
  ROLES = %w[user assistant system].freeze

  belongs_to :chat_session
  # Polymorphic sender — typically Person for user messages.
  # Optional because assistant/system messages have no sender record;
  # the `role` column is the authoritative discriminator.
  belongs_to :sender, polymorphic: true, optional: true

  validates :chat_session_id, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  scope :chronological, -> { order(:seq) }
  scope :by_role, ->(role) { where(role: role) }

  after_create :increment_chat_session_tokens

  private

  # Roll this message's token counts up to the parent session's total.
  # This avoids N+1 queries when computing session-level usage.
  def increment_chat_session_tokens
    chat_session.increment!(:total_tokens, input_tokens + output_tokens)
  end
end
