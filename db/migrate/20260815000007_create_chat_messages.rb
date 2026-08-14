# frozen_string_literal: true

# Stores individual messages within a chat session.
#
# Polymorphic sender (sender_type + sender_id) allows both Person and
# future AI-agent senders. chat_session_id FK ensures session ownership.
class CreateChatMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :chat_messages, options: "DEFAULT CHARSET=utf8mb3" do |t|
      t.bigint :chat_session_id, null: false

      # Polymorphic sender — 'Person' for user messages,
      # potentially 'AiAgent' for assistant messages in the future.
      t.string :sender_type, null: false
      t.string :sender_id, null: false, limit: 22

      t.text :content
      t.string :role, null: false, default: "user"
      t.integer :seq, default: 0, null: false

      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false

      t.json :metadata

      t.timestamps
    end

    add_index :chat_messages, [:chat_session_id, :created_at]
    add_index :chat_messages, [:sender_type, :sender_id]

    add_foreign_key :chat_messages, :chat_sessions
  end
end
