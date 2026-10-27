# frozen_string_literal: true

# 出品の表示指標の加算を担う小サービス（Issue #97・#98）。
#
# listings.times_viewed / total_sold は読み取り専用で加算処理が存在しなかった。
# マイページ・ホーム・ランキングの表示はこの値を読むため、ここで加算する。
# マイグレーション不要（既存カラムのみ）。Listing 本体には触らない。
class ListingStatsService
  #  bot・クローラの簡易判定（閲覧数に数えない）。
  BOT_PATTERN = /bot|crawl|spider|slurp|mediapartners|baidu|yandex|sogou|exabot|facebot|ia_archiver/i

  # 出品詳細の表示を1閲覧として数える。
  #
  # 方針（Issue #97 受入条件）:
  # - 出品者本人の閲覧は数えない（自己水増し防止）。
  # - bot・クローラは数えない（UA 判定）。
  # - 同一セッションの再読込は数える（厳密な二重防止はしない。仕様として記録）。
  #
  # @param listing [Listing] 表示された出品
  # @param viewer [Person, nil] 閲覧者（未ログインは nil）
  # @param user_agent [String, nil] リクエストの UA
  # @return [Boolean] 加算したら true
  def self.record_view(listing, viewer: nil, user_agent: nil)
    return false if listing.nil?
    return false if viewer.present? && listing.author_id == viewer.id
    return false if user_agent.present? && user_agent.match?(BOT_PATTERN)

    Listing.update_counters(listing.id, times_viewed: 1)
    true
  end
end
