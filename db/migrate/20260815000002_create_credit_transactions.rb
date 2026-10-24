# frozen_string_literal: true

class CreateCreditTransactions < ActiveRecord::Migration[6.1]
  def change
    create_table :credit_transactions do |t|
      # wallets.id is bigint (auto), so t.references works
      t.references :wallet, null: false, foreign_key: true

      t.string :transaction_type, null: false  # topup | usage_deduction | auto_recharge | refund
      t.integer :amount_cents, null: false      # Positive = credit, negative = debit

      # Polymorphic reference (for ChatSession, UserPlanSubscription, etc.)
      t.string :reference_type
      t.bigint :reference_id

      # JSON metadata stored as text (matches transaction_transitions pattern)
      t.text :metadata

      t.timestamps
    end

    add_index :credit_transactions, [:reference_type, :reference_id]
    add_index :credit_transactions, :transaction_type
  end
end
