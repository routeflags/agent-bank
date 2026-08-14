# frozen_string_literal: true

class CreateUsageRecords < ActiveRecord::Migration[6.1]
  def change
    create_table :usage_records do |t|
      # ai_models.id is bigint, so t.references works
      t.references :ai_model, foreign_key: true

      # FK to user_plan_subscriptions (bigint PK, nullable since pay_per_use has no subscription)
      t.bigint :user_plan_subscription_id

      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.integer :total_tokens, default: 0

      t.integer :cost_cents, default: 0    # Actual provider cost
      t.integer :charge_cents, default: 0  # Amount charged to user

      t.string :billing_model              # Snapshot of billing model at time of use
      t.string :currency, default: "USD"

      t.json :metadata

      t.timestamps
    end

    add_index :usage_records, [:user_plan_subscription_id, :created_at]

    # NOTE: chat_session_id FK is intentionally omitted (chat_sessions table arrives in Phase 3)
  end
end
