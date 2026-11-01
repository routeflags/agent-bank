# frozen_string_literal: true

# ペルソナ（出品）の評価表示（Issue #106 Phase 2b）。
#
# 集計値（`listings.avg_rating` / `listings.reviews_count`）は
# `ListingRatingService` が同期する。表示側の判定と整形を 5 つのテンプレートへ
# 散らすと「評価あり」の定義がぶれるため、ここに集約する。
#
# 「評価あり」の判定は **`reviews_count > 0`** を正とする。`avg_rating > 0` は
# 使わない: 既存の手動値（4.5 等）が `reviews_count=0` のまま残る過渡状態
# （マイグレーション直後〜正規化タスク実行前）で、実体の無い評価を出してしまう。
#
# 一覧カード（`/` と `/browse`）の `@listings` は検索結果の Struct
# （`ListingIndexViewUtils::ListingItem`）で集計カラムを持たない。そのため
# `HomepageController` が `{ listing_id => { avg_rating:, reviews_count: } }` を
# 1 クエリで先に読み、`preloaded:` で渡す（いいね数の `@listing_like_counts` と
# 同じ形。集計 1 件ごとに `Listing` を引く N+1 を避ける）。
module ListingRatingHelper
  # 評価が 1 件以上あるか。
  #
  # @param listing [Listing, ListingIndexViewUtils::ListingItem, nil]
  # @param preloaded [Hash{Integer => Hash{Symbol => Numeric}}, nil] 一覧カード用の事前読み込み値
  # @return [Boolean]
  def listing_rated?(listing, preloaded: nil)
    listing_rating_values(listing, preloaded)[:reviews_count].positive?
  end

  # 星の部分（例: '★ 4.2'）。評価が無いときは「—」。
  #
  # `avg_rating` は float のため、`round(1)` ではなく `number_with_precision` で
  # 小数 1 桁を保証する（4 は '4.0' と表示する）。
  #
  # @param listing [Listing, ListingIndexViewUtils::ListingItem, nil]
  # @param preloaded [Hash{Integer => Hash{Symbol => Numeric}}, nil]
  # @return [String]
  def listing_rating_stars(listing, preloaded: nil)
    values = listing_rating_values(listing, preloaded)
    return t('lamprey.listings.rating_dash') unless values[:reviews_count].positive?

    t('lamprey.listings.rating_stars',
      rating: number_with_precision(values[:avg_rating], precision: 1))
  end

  # 件数の部分（例: '(3)'）。評価が無いときは nil。
  #
  # 星と件数で色を分けたい画面（出品詳細の価格ボックス）が個別に要素を組めるよう、
  # 文字列を連結せずに分けて返す。
  #
  # @param listing [Listing, ListingIndexViewUtils::ListingItem, nil]
  # @param preloaded [Hash{Integer => Hash{Symbol => Numeric}}, nil]
  # @return [String, nil]
  def listing_rating_count(listing, preloaded: nil)
    values = listing_rating_values(listing, preloaded)
    return nil unless values[:reviews_count].positive?

    t('lamprey.listings.rating_count', count: values[:reviews_count])
  end

  # 1 つの文字列にまとめた評価（例: '★ 4.2 (3)'）。評価が無いときは「—」。
  #
  # @param listing [Listing, ListingIndexViewUtils::ListingItem, nil]
  # @param preloaded [Hash{Integer => Hash{Symbol => Numeric}}, nil]
  # @return [String]
  def listing_rating_text(listing, preloaded: nil)
    return listing_rating_stars(listing, preloaded: preloaded) unless listing_rated?(listing, preloaded: preloaded)

    "#{listing_rating_stars(listing, preloaded: preloaded)} #{listing_rating_count(listing, preloaded: preloaded)}"
  end

  private

  # 評価の集計値を返す。AR の `Listing` は自身のカラム、Struct は事前読み込み値。
  #
  # どちらにも無ければ未評価（0.0 / 0）として扱う（例外を投げない）。
  #
  # @param listing [Listing, ListingIndexViewUtils::ListingItem, nil]
  # @param preloaded [Hash{Integer => Hash{Symbol => Numeric}}, nil]
  # @return [Hash{Symbol => Numeric}]
  def listing_rating_values(listing, preloaded)
    return { avg_rating: 0.0, reviews_count: 0 } if listing.nil?

    if listing.respond_to?(:reviews_count) && listing.respond_to?(:avg_rating)
      return { avg_rating: listing.avg_rating.to_f, reviews_count: listing.reviews_count.to_i }
    end

    values = preloaded[listing.id] if preloaded && listing.respond_to?(:id)
    return { avg_rating: 0.0, reviews_count: 0 } unless values

    { avg_rating: values[:avg_rating].to_f, reviews_count: values[:reviews_count].to_i }
  end
end

