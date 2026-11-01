# frozen_string_literal: true

# 出品（ペルソナ）の評価集計（Issue #106 Phase 2a）。
#
# `listings.avg_rating` は書き込み処理が存在せず、初期データの手動値が残っていた。
# ランキング・一覧カード・出品詳細で「★4.2 (3件)」を出すには毎回 COUNT / AVG を
# 引くことになり N+1 になるため、`avg_rating` と `reviews_count` を集計カラムと
# して同期する。集計元は出品レビュー（`testimonials.listing_id` が一致するもの）。
#
# 集計値は「表示用のキャッシュ」であり出品そのものの更新ではないので、`update_columns`
# で書く（バリデーション・コールバック・`updated_at` を巻き込まない）。
class ListingRatingService
  # 星の尺度（1〜5）へ変換するための係数。grade(0..1) の平均を ×4 + 1 する。
  STARS_PER_GRADE = 4
  MIN_RATING = 1.0

  # 出品の `avg_rating` / `reviews_count` を再計算して書き戻す。
  #
  # 冪等: 再計算結果が現在値と同じなら書き込まない（無駄な UPDATE と
  # `saved_changes` の污染を避ける）。
  #
  # @param listing_or_id [Listing, Integer, String, nil]
  # @return [Listing, nil] 更新後の出品。出品が存在しなければ nil
  def self.recalculate!(listing_or_id)
    listing = find_listing(listing_or_id)
    return nil if listing.nil?

    attributes = computed_attributes(listing)
    return listing if unchanged?(listing, attributes)

    listing.update_columns(attributes)
    listing
  end

  # 現在のレビューから決まる集計値を返す（DB へは書かない）。
  #
  # rake のドライランでも同じ計算を使うため、書き込みと分離して公開する。
  #
  # @param listing_or_id [Listing, Integer, String, nil]
  # @return [Hash{Symbol=>Numeric}, nil] `{ reviews_count:, avg_rating: }`
  def self.expected_attributes(listing_or_id)
    listing = find_listing(listing_or_id)
    return nil if listing.nil?

    computed_attributes(listing)
  end

  # grade の平均を 1〜5 の評価尺度へ変換する（小数第1位で四捨五入）。
  # レビューが 0 件（平均が nil）のときは 0.0 を返す。0.0 は「評価なし」を表す
  # 既存の表現（手動値と同じ尺度。`displayed_grade` の grade*4+1 と同一の換算）。
  #
  # @param average_grade [Float, nil]
  # @return [Float] 1.0〜5.0、または 0.0
  def self.rating_from(average_grade)
    return 0.0 if average_grade.nil?

    (average_grade.to_f * STARS_PER_GRADE + MIN_RATING).round(1)
  end

  # 出品レビューの件数と grade の平均を 1 クエリで取る。
  #
  # `blocked`（モデレーションで非表示）は除外する。`grade` が NULL の行は平均に
  # 寄与しないため件数からも外し、`reviews_count` と平均の食い違いを防ぐ。
  #
  # @param listing_id [Integer]
  # @return [Array(Integer, Float|nil)]
  def self.aggregate(listing_id)
    count, average_grade = Testimonial
                           .non_blocked
                           .where(listing_id: listing_id)
                           .where.not(grade: nil)
                           .pick(Arel.sql("COUNT(*)"), Arel.sql("AVG(grade)"))
    [count.to_i, average_grade]
  end
  private_class_method :aggregate

  def self.computed_attributes(listing)
    reviews_count, average_grade = aggregate(listing.id)
    { reviews_count: reviews_count, avg_rating: rating_from(average_grade) }
  end
  private_class_method :computed_attributes

  def self.find_listing(listing_or_id)
    return listing_or_id if listing_or_id.is_a?(Listing)
    return nil if listing_or_id.blank?

    Listing.find_by(id: listing_or_id)
  end
  private_class_method :find_listing

  def self.unchanged?(listing, attributes)
    attributes.all? { |column, value| listing.public_send(column) == value }
  end
  private_class_method :unchanged?
end
