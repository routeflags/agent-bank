# frozen_string_literal: true

# Issue #106 Phase 2a: `listings.reviews_count` の追加。
#
# 一覧カード・ランキングで「★4.2 (3件)」を出すのに毎回 COUNT すると N+1 になる
# ため、`avg_rating` と対になる集計カラムを持つ。既存行はデフォルト 0 で埋まる
# （実件数とのずれは `lamprey:normalize_listing_ratings` で正規化する）。
class AddReviewsCountToListings < ActiveRecord::Migration[8.1]
  def change
    add_column :listings, :reviews_count, :integer, default: 0, null: false
  end
end
