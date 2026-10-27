module ListingIndexService::Search::DatabaseSearchHelper

  module_function

  def success_result(count, listings, includes)
    Result::Success.new(
      {count: count, listings: listings.map { |l| ListingIndexService::Search::Converters.listing_hash(l, includes) }})
  end

  def fetch_from_db(community_id:, search:, included_models:, includes:)
    where_opts = HashUtils.compact(
      {
        community_id: community_id,
        author_id: search[:author_id],
        deleted: 0,
        listing_shape_id: Maybe(search[:listing_shape_ids]).or_else(nil)
      })

    scope = Listing
    scope = scope.use_homepage_index if !search[:include_closed] && !search[:author_id]
    scope = scope.currently_open unless search[:include_closed]

    # Category filter — the search engine (Sphinx) applies :categories, but
    # this DB fallback previously ignored it, so category navigation showed
    # unfiltered results whenever the engine was unavailable.
    scope = scope.where(category_id: search[:categories]) if search[:categories].present?

    # AI Persona filters
    scope = scope.run_online if search[:run_mode] == 'run_online'
    scope = scope.download_mode if search[:run_mode] == 'download'
    scope = scope.with_ai_model(search[:ai_model_id]) if search[:ai_model_id].present?
    scope = scope.persona_only if search[:has_persona].present?

    listings = scope.where(where_opts)
                 .includes(included_models)
                 .order(order_clause(search[:sort_by]))
                 .paginate(per_page: search[:per_page], page: search[:page])

    success_result(listings.total_entries, listings, includes)
  end

  # 一覧の並び順（Issue #80 / #81）。
  #
  # `:sort` は検索エンジン（Sphinx）用のキーで、DB フォールバックでは無視される。
  # そのためホーム／一覧のタブは `:sort_by` で渡し、ここで並びを切り替える。
  # Sphinx 検索になる条件（キーワード・カテゴリ等）ではこの並びは使われない。
  #
  # @param sort_by [String, nil] "popular" / "newest" / "rating"
  # @return [String] ORDER BY 句
  def order_clause(sort_by)
    case sort_by.to_s
    when "newest"
      "listings.created_at DESC, listings.id DESC"
    when "rating"
      "listings.avg_rating DESC, listings.created_at DESC, listings.id DESC"
    else
      "listings.sort_date DESC"
    end
  end

  # TODO: This should probably be rethought when the Indexer and the
  # new Search API is finished and in use
  def needs_db_query?(search)
    search[:author_id].present? || search[:include_closed] == true
  end

  # Determines whether the search request must go through the external
  # search engine (Sphinx).  Persona-related filters (:run_mode,
  # :ai_model_id, :has_persona) are intentionally excluded here so they
  # are always handled by the DB query path in #fetch_from_db.
  def needs_search?(search)
    [
      :keywords,
      :latitude,
      :longitude,
      :distance_max,
      :sort,
      :listing_shape_id,
      :listing_shape_ids,
      :categories,
      :fields,
      :price_cents
    ].any? { |field| search[field].present? }
  end

end
