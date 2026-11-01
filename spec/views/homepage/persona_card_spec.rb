# frozen_string_literal: true

require 'spec_helper'

# Issue #106 Phase 2b: 一覧カード（トップ / 一覧の .cards グリッド）の評価表示。
#
# カードは検索結果の Struct（`ListingIndexViewUtils::ListingItem`）を受け取る
# （`listing.url` を使うため AR の `Listing` は渡せない）。そのため評価は
# コントローラの事前読み込み（`@listing_ratings`）経由でしか存在しない。
#
# - 評価があるカードだけ「★ 4.0 (1)」を出す
# - 未評価のカードは★を出さない（Issue #129 のいいね数はそのまま）
RSpec.describe "一覧カードの評価表示", type: :view do
  # カードの描画に必要な最小限の Struct。画像を 1 枚持たせて `image_tag`
  # （アセットパイプライン）を通さない（この worktree は webpack 成果物が無い）。
  def listing_item(title, id: 1)
    image = ListingIndexViewUtils::ListingImage.new("/img/t.jpg", "/img/m.jpg", "/img/l.jpg")
    ListingIndexViewUtils::ListingItem.new(
      id, "/listings/#{id}", title, nil, nil, nil, nil, nil,
      nil, "説明文", [image], Money.new(1000, "JPY")
    )
  end

  def render_card(listing, listing_ratings: nil)
    assigns = {
      listing_like_counts: Hash.new(0),
      liked_listing_ids: Set.new,
      current_user: nil
    }
    assigns[:listing_ratings] = listing_ratings if listing_ratings

    I18n.with_locale(:ja) do
      ApplicationController.render(
        partial: "homepage/persona_card",
        locals: { listing: listing },
        assigns: assigns
      )
    end
  end

  it "評価があるカードは★と件数を出す" do
    html = render_card(listing_item("評価ありのペルソナ"),
                       listing_ratings: { 1 => { avg_rating: 4.25, reviews_count: 3 } })

    expect(html).to include("class=\"rating\"")
    expect(html).to include("★ 4.3 (3)")
  end

  it "レビュー 1 件のカードは★ 4.0 (1) を出す" do
    html = render_card(listing_item("評価ありのペルソナ"),
                       listing_ratings: { 1 => { avg_rating: 4.0, reviews_count: 1 } })

    expect(html).to include("★ 4.0 (1)")
  end

  it "未評価のカードは★を出さず、いいね数と価格は出す" do
    # Phase 2a の正規化前の状態（手動値 4.5 / レビュー 0 件）。
    html = render_card(listing_item("未評価のペルソナ"),
                       listing_ratings: { 1 => { avg_rating: 4.5, reviews_count: 0 } })

    expect(html).not_to include("★")
    expect(html).not_to include("rating")
    expect(html).to include("♡ 0")
    expect(html).to include("¥1,000")
  end

  it "事前読み込みが無い Struct でも落ちず、★ を出さない" do
    html = render_card(listing_item("事前読み込みなしのペルソナ"))

    expect(html).to include("事前読み込みなしのペルソナ")
    expect(html).not_to include("★")
  end
end


