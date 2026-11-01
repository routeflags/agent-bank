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
#
# 同時実行について: 「集計 SELECT → UPDATE」は出品行をロックしないため、ほぼ同時に
# 2 件の評価が commit すると、古い集計で上書きされる可能性がある（最終値が 1 件分
# ずれる）。評価の投稿頻度と、次の評価イベント／`lamprey:normalize_listing_ratings`
# で自己修復できることを踏まえ、ここではロックを取らない（判定を増やすより、ずれたら
# 直せる状態を優先する）。厳密さが必要になったら `Listing.lock.find_by(id:)` で
# 出品行を直列化する。
#
# なお `reviews_count` は counter_cache ではない。`belongs_to :listing, counter_cache:`
# を後から足すと二重計上し、しかも取引レビュー（listing_id が NULL）を数えて
# しまうので使わないこと。
class ListingRatingService
  # 星の尺度（1〜5）へ変換するための係数。grade(0..1) の平均を ×4 + 1 する。
  STARS_PER_GRADE = 4
  MIN_RATING = 1.0
  MAX_RATING = 5.0

  # `listings.avg_rating` は float（単精度）で、SQL 側で比較すると微小な誤差が出る
  # （例: `CAST(avg_rating AS DOUBLE)` は 4.199999809265137）。AR の読み出しは
  # テキストプロトコルで 1 桁の値がそのまま返るため実害はないが、比較を関数に
  # 閉じておくため許容差で「同じ値」を判定する。
  FLOAT_TOLERANCE = 1e-6

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
    return listing if same_values?(listing, attributes)

    listing.update_columns(attributes)
    listing
  end

  # 集計カラムが既に最新か（再計算しても値が変わらないか）。
  #
  #  rake のドライランで「実質同じなのに書き換え対象」と報告しないために使う。
  #
  # @param listing [Listing, nil]
  # @return [Boolean]
  def self.up_to_date?(listing)
    return false if listing.nil?

    same_values?(listing, computed_attributes(listing))
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
  # 範囲外の grade（AR の検証を迂回した行）でも表示が壊れないよう 1〜5 に丸める。
  #
  # @param average_grade [Float, nil]
  # @return [Float] 1.0〜5.0、または 0.0
  def self.rating_from(average_grade)
    return 0.0 if average_grade.nil?

    (average_grade.to_f * STARS_PER_GRADE + MIN_RATING).round(1).clamp(MIN_RATING, MAX_RATING)
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

    # listings には TEXT 列（description / skill_markdown）があるため、集計に
    # 必要な列だけ読む（評価投稿のたびに全列 SELECT しない）。
    Listing.select(:id, :avg_rating, :reviews_count).find_by(id: listing_or_id)
  end
  private_class_method :find_listing

  def self.same_values?(listing, attributes)
    attributes.all? do |column, value|
      current = listing.public_send(column)
      next false if current.nil?

      if value.is_a?(Integer)
        current.to_i == value
      else
        (current.to_f - value.to_f).abs < FLOAT_TOLERANCE
      end
    end
  end
  private_class_method :same_values?
end
