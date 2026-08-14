# frozen_string_literal: true

class CreateUserPlanSubscriptions < ActiveRecord::Migration[6.1]
  def change
    # people.id is varchar(22) with utf8mb3 charset and NO unique index,
    # so the table charset must match and FK to people is skipped.
    create_table :user_plan_subscriptions, options: "DEFAULT CHARSET=utf8mb3" do |t|
      # FK to people — people.id is varchar(22) without UNIQUE constraint,
      # so we use string and skip the formal FK (app-level integrity).
      t.string :person_id, limit: 22, null: false
      # FK to listings — listings.id is int (32-bit)
      t.integer :listing_id, null: false

      t.string :billing_model, null: false               # subscription | pay_per_use | subscription_with_overage
      t.string :status, null: false, default: "active"    # active | paused | canceled | past_due

      t.datetime :current_period_start
      t.datetime :current_period_end

      t.integer :period_usage_tokens, default: 0          # Tokens consumed in current billing period
      t.boolean :cancel_at_period_end, default: false

      t.string :stripe_subscription_id                    # Stripe Subscription ID (Phase 4/5)

      t.timestamps
    end

    add_index :user_plan_subscriptions, :status
    add_index :user_plan_subscriptions, :stripe_subscription_id
    add_index :user_plan_subscriptions, [:person_id, :status]
    add_index :user_plan_subscriptions, [:listing_id, :person_id]

    # listings.id has a standard integer PK, so FK is safe
    add_foreign_key :user_plan_subscriptions, :listings

    # NOTE: people.id lacks a UNIQUE constraint (Sharetribe legacy),
    # so a formal FK to people cannot be added. Referential integrity
    # is enforced at the application level.
    # NOTE: chat_session_id FK is intentionally omitted (Phase 3).
  end
end
