class AddFreemiusSubscriptionIdToUserPlanSubscriptions < ActiveRecord::Migration[8.1]
  def change
    change_table :user_plan_subscriptions, bulk: true do |t|
      t.string :freemius_subscription_id
      t.index :freemius_subscription_id
    end
  end
end
