# frozen_string_literal: true

# Phase 3 review fix: Make sender polymorphic association optional.
#
# System/assistant messages do not have a real sender record, so
# sender_type and sender_id must accept NULL. The `role` column is
# the authoritative discriminator for message origin.
class MakeChatMessageSenderOptional < ActiveRecord::Migration[6.1]
  def change
    change_column_null :chat_messages, :sender_type, true
    change_column_null :chat_messages, :sender_id, true
  end
end
