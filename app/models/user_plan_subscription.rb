# frozen_string_literal: true

# == Schema Information
#
# Table name: user_plan_subscriptions
#
#  id                      :bigint           not null, primary key
#  person_id               :string(22)       not null
#  listing_id              :integer          not null
#  billing_model           :string           not null
#  status                  :string           default("active"), not null
#  current_period_start    :datetime
#  current_period_end      :datetime
#  period_usage_tokens     :integer          default(0)
#  cancel_at_period_end    :boolean          default(FALSE)
#  stripe_subscription_id  :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_user_plan_subscriptions_on_listing_id_and_person_id    (listing_id,person_id)
#  index_user_plan_subscriptions_on_person_id_and_status        (person_id,status)
#  index_user_plan_subscriptions_on_stripe_subscription_id      (stripe_subscription_id)
#  index_user_plan_subscriptions_on_status                      (status)
#

class UserPlanSubscription < ApplicationRecord
  belongs_to :person
  belongs_to :listing

  has_many :user_plan_subscription_transitions, class_name: "UserPlanSubscriptionTransition", autosave: false, dependent: :destroy
  has_many :transitions, class_name: "UserPlanSubscriptionTransition", autosave: false, dependent: :destroy, foreign_key: :user_plan_subscription_id

  # Read the current state from the most recent transition record.
  def current_state
    last = transitions.where(most_recent: true).last
    last&.to_state || "active"
  end

  # Delegate to the state machine for transitions.
  #
  # Usage:
  #   sub.transition_to!(:paused)
  #   sub.transition_to!(:active)
  def transition_to!(new_state, metadata = {})
    state_machine.transition_to!(new_state, metadata)
  end

  def transition_to(new_state, metadata = {})
    state_machine.transition_to(new_state, metadata)
  end

  def can_transition_to?(new_state)
    state_machine.can_transition_to?(new_state)
  end

  private

  def state_machine
    UserPlanSubscriptionStateMachine.new(
      self,
      transition_class: UserPlanSubscriptionTransition,
      association_name: :user_plan_subscription_transitions
    )
  end
end
