class RankingsController < ApplicationController

  # Allow rankings to be viewed before email confirmation
  skip_before_action :cannot_access_without_confirmation

  # 並び順（Issue #106 Phase 2b）: 実データを先に見て、評価は同点時のタイブレーク。
  #
  # 以前は avg_rating が第一キーだったが、avg_rating は 2026-11 の Phase 2a まで
  # 書き込み処理が無く、レビュー 0 件の出品に手動値（4.5 等）が入っていた。そのため
  # 「評価の実体が無い 6 件が常に上位」という実態と無関係な並びになっていた。
  # 販売数・閲覧数（どちらも実データ）を主キーにし、評価は同点を崩すときだけ使う。
  # 最後の id は全キーが同点のときの決定的な順序（limit で切り落とす位置を安定
  # させる）。
  def index
    @ranked_listings = @current_community.listings
                                          .currently_open
                                          .includes(:author)
                                          .order(total_sold: :desc, times_viewed: :desc, avg_rating: :desc, id: :asc)
                                          .limit(20)
  end
end
