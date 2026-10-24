# frozen_string_literal: true

# Tracks AI persona chat sessions between a user and a listing (persona).
#
# people.id is varchar(22) without UNIQUE, so DB-level FK is skipped.
# listings.id is integer (32-bit), so FK is safe.
class CreateChatSessions < ActiveRecord::Migration[6.1]
  def change
    create_table :chat_sessions, options: "DEFAULT CHARSET=utf8mb3" do |t|
      # FK to people — people.id is varchar(22) without UNIQUE constraint,
      # so a formal FK cannot be added. Referential integrity is app-level.
      t.string :person_id, limit: 22, null: false

      # FK to listings — listings.id is int (32-bit) with standard integer PK
      t.integer :listing_id, null: false

      t.string :status, null: false, default: "active"
      t.string :billing_model
      t.datetime :started_at
      t.datetime :ended_at
      t.integer :total_tokens, default: 0, null: false

      t.timestamps
    end

    add_index :chat_sessions, [:person_id, :status]
    add_index :chat_sessions, [:listing_id, :person_id]

    add_foreign_key :chat_sessions, :listings

    # NOTE: people.id lacks a UNIQUE constraint (Sharetribe legacy),
    # so a formal FK to people cannot be added. Referential integrity
    # is enforced at the application level.
  end
end
