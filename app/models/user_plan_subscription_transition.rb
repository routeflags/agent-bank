# frozen_string_literal: true

# == Schema Information
#
# Table name: user_plan_subscription_transitions
#
#  id                           :bigint           not null, primary key
#  to_state                     :string
#  metadata                     :text
#  sort_key                     :integer          default(0)
#  user_plan_subscription_id    :bigint           not null
#  most_recent                  :boolean
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_user_plan_subscription_transitions_unique  (sort_key,user_plan_subscription_id) UNIQUE
#  index_user_plan_subscription_transitions_on_user_plan_subscription_id  (user_plan_subscription_id)
#

class UserPlanSubscriptionTransition < ApplicationRecord
  include Statesman::Adapters::ActiveRecordTransition

  belongs_to :user_plan_subscription, inverse_of: :transitions, touch: true
end
