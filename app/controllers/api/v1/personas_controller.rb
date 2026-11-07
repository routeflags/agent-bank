# frozen_string_literal: true

# AI ペルソナ（出品）の公開情報を返す読み取り専用 API（Issue #145）。
#
# MCP サーバー（#143）の search_personas / get_persona が使う。
# 認証は API 共通 concern（#142）で、要求 scope は read。
#
# 返すのは /browse で誰でも見られる情報だけ。`skill_markdown`
# （AI への指示文＝出品者のノウハウ）は全文を返さず、`skill_excerpt` に
# 先頭 200 字だけを載せる。ダウンロード実行を提供しているペルソナだけ
# `skill_available_for_download: true` を返す（本文の受け渡しは実行系 #144）。
#
# 絞り込みと並び順は /browse と共通（PersonaSearchQuery）。
class API::V1::PersonasController < ApplicationController
  include APIAuthenticatable

  # 参照専用の API。
  api_requires_scope :read

  # description は先頭 200 字まで（`truncate` の長さには省略記号を含む）。
  DESCRIPTION_LENGTH = 200
  # スキルの抜粋。全文は返さない。
  SKILL_EXCERPT_LENGTH = 200

  # GET /api/v1/personas
  #
  # @param query [String] キーワード（空なら全件）
  # @param category [String] カテゴリの url か id
  # @param sort [String] popular / newest / rating
  # @param limit [Integer] 1 ページの件数（既定 20、上限 50）
  # @param page [Integer] ページ番号（既定 1）
  def index
    persona_search.call
      .on_success { |page| render json: { personas: serialize_list(page) } }
      .on_error { |error_msg|
        Rails.logger.warn("[personas_api] search failed: #{error_msg}")
        render json: { error: "ペルソナの検索に失敗しました" }, status: :service_unavailable
      }
  end

  # GET /api/v1/personas/:id
  #
  # 存在しない・非公開（非公開・期限切れ・削除済み・未承認）は 404。
  def show
    listing = visible_listings.find_by(id: params[:id])

    unless listing
      return render json: { error: "ペルソナが見つかりません" }, status: :not_found
    end

    render json: { persona: serialize_detail(listing) }
  end

  private

  def persona_search
    PersonaSearchQuery.new(
      community: api_community,
      query: params[:query],
      category: params[:category],
      sort: params[:sort],
      page: params[:page],
      per_page: params[:limit]
    )
  end

  # 公開されている出品だけ。判定は /browse と同じ `Listing.currently_open`。
  def visible_listings
    Listing.where(community_id: api_community.id).currently_open
  end

  def serialize_list(page)
    listings = load_listings(page.listing_ids)
    categories = load_categories(listings)

    listings.map { |listing| serialize_summary(listing, categories) }
  end

  # 検索の並び順を保ったまま AR レコードを読む。
  # 検索結果の Struct は評価（avg_rating / reviews_count）や run_mode を
  # 持たないため、一覧分を 1 クエリで引き直す。
  #
  # @param listing_ids [Array<Integer>] 検索結果の並び順
  # @return [Array<Listing>]
  def load_listings(listing_ids)
    return [] if listing_ids.empty?

    by_id = Listing.where(id: listing_ids).index_by(&:id)
    listing_ids.filter_map { |id| by_id[id] }
  end

  # カテゴリ名はカテゴリごとに翻訳を引くため、N+1 を避けて 1 クエリで読む。
  #
  # @return [Hash{Integer => Category}]
  def load_categories(listings)
    ids = listings.map(&:category_id).compact.uniq
    return {} if ids.empty?

    Category.where(id: ids).includes(:translations).index_by(&:id)
  end

  def serialize_summary(listing, categories)
    {
      id: listing.id,
      title: listing.title,
      description: excerpt(listing.description, DESCRIPTION_LENGTH),
      price_cents: listing.price_cents,
      category: serialize_category(categories[listing.category_id]),
      avg_rating: listing.avg_rating.to_f,
      reviews_count: listing.reviews_count.to_i,
      run_modes: listing.available_run_modes
    }
  end

  def serialize_detail(listing)
    serialize_summary(listing, load_categories([listing])).merge(
      skill_excerpt: excerpt(listing.skill_markdown, SKILL_EXCERPT_LENGTH),
      skill_available_for_download: skill_available_for_download?(listing)
    )
  end

  # カテゴリは id / url / 表示名を返す。url は絞り込みの `category` に
  # そのまま渡せる。
  def serialize_category(category)
    return nil if category.nil?

    {
      id: category.id,
      url: category.url,
      name: category.display_name(I18n.locale)
    }
  end

  # 先頭 `length` 字まで（`truncate` は省略記号を含めて length 字以内）。
  def excerpt(text, length)
    text.to_s.strip.truncate(length)
  end

  # スキル本文を渡せるのは、ダウンロード実行を提供していて、かつ本文がある
  # ペルソナだけ。実行モードに download が無い場合はサーバー側でしか使えない。
  def skill_available_for_download?(listing)
    listing.available_run_modes.include?("download") && listing.skill_markdown.present?
  end
end
