# frozen_string_literal: true

# ペルソナ（AI 出品）検索の共通クエリ（Issue #145）。
#
# /ja/browse の検索（HomepageController#index → #find_listings）とまったく同じ
# `search` ハッシュを組み立て、同じ経路（ListingIndexService::API）で引く。
# 「一覧に出るもの」と JSON API（/api/v1/personas）が返すものが同じ絞り込み・
# 同じ並び順になることを、この 1 クラスで担保する。
#
# HTML 側の discovery API 経路（feature flag `searchpage_v1`）はページ専用の
# 実験経路なのでここには複製しない。通常の一覧と同じ検索サービスを通る。
class PersonaSearchQuery
  # 一覧の並び順（Issue #80 / #81）。ブラウズも API もこの 3 つだけを受け付け、
  # 未知の値は既定に落とす。値の定義はここが正本で、HomepageController も
  # このメソッドを使う。
  SORT_ORDERS = %w[popular newest rating].freeze
  DEFAULT_SORT = "popular"

  # API の `limit` の既定値と上限（上限を超えたら 50 に、0 以下なら 1 に
  # クランプする）。
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 50

  # 検索結果。`listing_ids` は一覧の並び順そのまま。
  Page = Struct.new(:listing_ids, :total_entries, keyword_init: true)

  class << self
    # 並び順の値を正規化する。
    #
    # @param sort [String, nil] `?sort=` の値
    # @return [String] "popular" / "newest" / "rating"
    def sort_order(sort)
      value = sort.to_s
      SORT_ORDERS.include?(value) ? value : DEFAULT_SORT
    end

    # 1 ページの件数を正規化する。
    #
    # 未指定・数値でない値は既定件数、範囲外（0・負数・上限超え）は
    # 1〜MAX_PER_PAGE にクランプする。`limit=0` は「0 件」ではなく 1 件。
    #
    # @param limit [String, Integer, nil] `?limit=` の値
    # @return [Integer]
    def per_page(limit)
      number = Integer(limit.to_s, exception: false)
      return DEFAULT_PER_PAGE if number.nil?

      number.clamp(1, MAX_PER_PAGE)
    end

    # ページ番号を正規化する。未指定・0 以下は 1 ページ目として扱う。
    #
    # @param page [String, Integer, nil] `?page=` の値
    # @return [Integer]
    def page_number(page)
      number = Integer(page.to_s, exception: false)
      return 1 if number.nil?

      [number, 1].max
    end
  end

  attr_reader :community, :keywords, :category, :sort, :page, :per_page

  # @param community [Community] 検索対象のマーケットプレイス
  # @param query [String, nil] キーワード（空・空白のみは絞り込みなし）
  # @param category [String, nil] カテゴリの url か id
  # @param sort [String, nil] "popular" / "newest" / "rating"
  # @param page [String, Integer, nil] ページ番号
  # @param per_page [String, Integer, nil] 1 ページの件数（API の `limit`）
  def initialize(community:, query: nil, category: nil, sort: nil, page: nil, per_page: nil)
    @community = community
    @keywords = query.to_s.strip.presence
    @category = category.to_s.strip.presence
    @sort = self.class.sort_order(sort)
    @page = self.class.page_number(page)
    @per_page = self.class.per_page(per_page)
  end

  # HomepageController#find_listings と同じキー構成の `search` ハッシュ。
  #
  # 位置引数由来のフィルタ（listing_shape / 価格帯 / カスタムフィールド）は
  # API では受け付けないので空にしておく。HTML 側と同じキーを揃えることで、
  # 検索サービス側の分岐（DB フォールバック / 検索エンジン）も同じになる。
  def search_params
    {
      categories: categories,
      listing_shape_ids: [],
      price_cents: nil,
      keywords: keywords,
      fields: [],
      per_page: per_page,
      page: page,
      price_min: nil,
      price_max: nil,
      locale: I18n.locale,
      include_closed: false,
      sort: nil,
      sort_by: sort
    }
  end

  # 検索を実行する。
  #
  # @return [Result] Result::Success(Page) / Result::Error
  def call
    ListingIndexService::API::API.listings.search(
      community_id: community.id,
      search: search_params,
      # この API は要約だけを返すため、関連（author / listing_images）は
      # 検索時に読まない。必要なカラムは呼び出し側が 1 クエリで引き直す。
      includes: [],
      engine: FeatureFlagHelper.search_engine,
      raise_errors: false
    ).and_then { |response|
      Result::Success.new(
        Page.new(
          listing_ids: response[:listings].map { |listing| listing[:id] },
          total_entries: response[:count]
        )
      )
    }
  end

  private

  # カテゴリ絞り込み（url か id）。
  #
  # /browse と同じく、該当するカテゴリが無ければ絞り込まない（全件扱い）。
  # カテゴリは配下のサブカテゴリを含む。
  #
  # @return [Array<Integer>, nil]
  def categories
    return nil if category.blank?

    community.categories.find_by_url_or_id(category)&.own_and_subcategory_ids
  end
end
