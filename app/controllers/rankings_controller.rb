class RankingsController < ApplicationController

  # Allow rankings to be viewed before email confirmation
  skip_before_action :cannot_access_without_confirmation

  def index
    @ranked_listings = @current_community.listings
                                         .currently_open
                                         .includes(:author)
                                         .order(avg_rating: :desc, total_sold: :desc, times_viewed: :desc)
                                         .limit(20)
  end
end
