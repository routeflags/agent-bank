# frozen_string_literal: true

# Issue #151: レビューへの「いいね」数の counter cache。
#
# 増減は `TestimonialLike` の `belongs_to :testimonial, counter_cache: :likes_count`
# が書き込む。`listings.avg_rating` / `reviews_count`（ListingRatingService）は
# レビュー本文の grade から決まる集計であり、いいねは評価に影響させないため
# 別カラムに持つ。
class AddLikesCountToTestimonials < ActiveRecord::Migration[8.1]
  def change
    add_column :testimonials, :likes_count, :integer, null: false, default: 0
  end
end
