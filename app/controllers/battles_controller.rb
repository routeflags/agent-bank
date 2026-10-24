class BattlesController < ApplicationController

  # Allow battles page to be viewed before email confirmation
  skip_before_action :cannot_access_without_confirmation

  def index; end
end
