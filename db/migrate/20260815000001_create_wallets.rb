# frozen_string_literal: true

class CreateWallets < ActiveRecord::Migration[6.1]
  def change
    # people.id is varchar(22) with utf8mb3 charset and NO unique index,
    # so the table charset must match and FK to people is skipped.
    create_table :wallets, options: "DEFAULT CHARSET=utf8mb3" do |t|
      # FK to people — people.id is varchar(22) without UNIQUE constraint,
      # so we use string and skip the formal FK (app-level integrity).
      t.string :person_id, limit: 22, null: false
      # FK to communities — communities.id is int (32-bit)
      t.integer :community_id, null: false

      t.integer :balance_cents, default: 0, null: false
      t.string :currency, default: "USD", null: false

      t.timestamps
    end

    add_index :wallets, [:person_id, :community_id], unique: true

    # communities.id has a standard integer PK, so FK is safe
    add_foreign_key :wallets, :communities

    # NOTE: people.id lacks a UNIQUE constraint (Sharetribe legacy),
    # so a formal FK to people cannot be added. Referential integrity
    # is enforced at the application level.
  end
end
