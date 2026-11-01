# frozen_string_literal: true

# Issue #106 Phase 2a: 既存データの評価集計の正規化。
#
# `listings.avg_rating` は書き込み処理が無かったため、初期データの手動値（4.5 等）
# が残っている。Testimonial からの再計算結果と突き合わせ、**ずれている出品だけ**を
# 直す。既定はドライラン（対象の出力のみ）で、適用は `COMMIT=1`（既存の
# `lib/tasks/import.rake` と同じ流儀）。
#
#   bin/rails "lamprey:normalize_listing_ratings"            # ドライラン
#   COMMIT=1 bin/rails "lamprey:normalize_listing_ratings"   # 適用
#
# タスク本体は薄く保ち、判定・出力は module 側に置く（既存の
# lib/tasks/lamprey_audit.rake と同じ構成。rake ファイルは起動時に評価されるため、
# トップレベルにメソッドを置くと Object を汚す）。
module LampreyListingRatings
  module_function

  # @param apply [Boolean] true なら実際に書き換える（COMMIT=1）
  def run(apply:)
    puts "[lamprey:normalize_listing_ratings] mode=#{apply ? 'commit' : 'dry-run'}"

    targets = normalization_targets

    if targets.empty?
      puts "対象 0 件（すべて整合している）"
      return
    end

    targets.each { |target| puts target[:description] }
    puts summary(targets)

    if apply
      targets.each { |target| ListingRatingService.recalculate!(target[:listing]) }
      puts "適用しました: #{targets.size} 件"
    else
      puts "ドライラン: DB は変更していません。適用するには COMMIT=1 を付けて再実行してください。"
    end
  end

  # 集計結果と現在値がずれている出品を集める。
  #
  # @return [Array<Hash>] `{ listing:, current:, expected:, description: }`
  def normalization_targets
    Listing.order(:id).find_each(order: :asc).filter_map do |listing|
      expected = ListingRatingService.expected_attributes(listing)
      next if expected.nil?

      current = { reviews_count: listing.reviews_count, avg_rating: listing.avg_rating }
      next if current == expected

      {
        listing: listing,
        current: current,
        expected: expected,
        description: describe_target(listing, current, expected)
      }
    end
  end

  def summary(targets)
    rating_changes = targets.count { |target| target[:current][:avg_rating] != target[:expected][:avg_rating] }
    count_changes = targets.count { |target| target[:current][:reviews_count] != target[:expected][:reviews_count] }
    "対象 #{targets.size} 件（avg_rating: #{rating_changes} 件 / reviews_count: #{count_changes} 件）"
  end

  def describe_target(listing, current, expected)
    format(
      "  listing #%d %s: avg_rating %s -> %s / reviews_count %d -> %d",
      listing.id,
      listing.title.to_s,
      current[:avg_rating],
      expected[:avg_rating],
      current[:reviews_count],
      expected[:reviews_count]
    )
  end
end

namespace :lamprey do
  desc "listings の avg_rating / reviews_count を Testimonial から再計算して正規化する（既定はドライラン、適用は COMMIT=1）"
  task normalize_listing_ratings: :environment do
    LampreyListingRatings.run(apply: ENV["COMMIT"] == "1")
  end
end
