# 一覧ページのページネーションリンクビルダー（will_paginate 用）。
#
# デフォルトの LinkRenderer は url_for(controller:, action:) で URL を組み立てる
# ため、同一アクション（homepage#index）への複数ルートのうち /s を選び、
# /s → / の 307 リダイレクトを経由してトップページへ戻ってしまう（Issue #26）。
# パス生成は一覧ページ/トップの切り替えルール（raku_listing_index_path）に委ねる。
class ListingPaginationRenderer < WillPaginate::ActionView::LinkRenderer
  def url(page)
    @template.raku_listing_index_path(query_params.merge(page: page))
  end

  private

  # 現在のリクエストの検索パラメータ（ページ数は除く）。
  # controller/action/utf8 は raku_listing_index_path 側でも除去される。
  def query_params
    @query_params ||= begin
      request_params = @template.params
      request_params = request_params.to_unsafe_h if request_params.respond_to?(:to_unsafe_h)
      request_params.except(:controller, :action, :page, :format, :_method)
    end
  end
end
