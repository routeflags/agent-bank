# frozen_string_literal: true

class UserPlanSubscriptionStateMachine
  include Statesman::Machine

  state :active, initial: true
  state :paused
  state :canceled
  state :past_due

  transition from: :active,   to: [:paused, :canceled, :past_due]
  transition from: :paused,   to: [:active, :canceled]
  transition from: :past_due, to: [:active, :canceled]
end
