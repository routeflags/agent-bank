# frozen_string_literal: true

class CreateUserPlanSubscriptionTransitions < ActiveRecord::Migration[6.1]
  def change
    create_table :user_plan_subscription_transitions do |t|
      t.string :to_state
      t.text :metadata
      t.integer :sort_key, default: 0
      t.bigint :user_plan_subscription_id, null: false
      t.boolean :most_recent

      t.timestamps
    end

    add_index :user_plan_subscription_transitions, [:sort_key, :user_plan_subscription_id],
              unique: true, name: "index_user_plan_subscription_transitions_unique"
    add_index :user_plan_subscription_transitions, :user_plan_subscription_id,
              name: "index_user_plan_sub_transitions_on_sub_id"
  end
end
