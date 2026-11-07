# frozen_string_literal: true

require 'rails_helper'

# ペルソナ検索クエリ（Issue #145）。/ja/browse と API が共有する並び順と
# `search` ハッシュの組み立てを固定する。
RSpec.describe PersonaSearchQuery do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:default_category) do
    category = FactoryBot.create(:category, community: community)
    category.translation_attributes = { en: { name: "スキル" } }
    category.save!
    category
  end
  let(:category) { default_category }

  def create_listing(title:, sort_date: 1.day.ago, category: nil)
    listing = FactoryBot.create(:listing, community_id: community.id, author: person,
                                          category: category || default_category,
                                          title: title)
    listing.update_columns(sort_date: sort_date)
    listing
  end

  describe ".sort_order" do
    it "受け付ける値をそのまま返す" do
      expect(described_class.sort_order("newest")).to eq("newest")
      expect(described_class.sort_order("rating")).to eq("rating")
      expect(described_class.sort_order("popular")).to eq("popular")
    end

    it "未知の値・nil は既定（popular）に落とす" do
      expect(described_class.sort_order("unknown")).to eq("popular")
      expect(described_class.sort_order(nil)).to eq("popular")
    end
  end

  describe ".per_page" do
    it "未指定・数値でない値は既定（20）" do
      expect(described_class.per_page(nil)).to eq(20)
      expect(described_class.per_page("")).to eq(20)
      expect(described_class.per_page("abc")).to eq(20)
    end

    it "上限（50）を超える値は 50 にクランプする" do
      expect(described_class.per_page("51")).to eq(50)
      expect(described_class.per_page("5.5")).to eq(20) # 数値ではない
      expect(described_class.per_page("1000")).to eq(50)
    end

    it "0 ・負数は 1 にクランプする" do
      expect(described_class.per_page("0")).to eq(1)
      expect(described_class.per_page("-3")).to eq(1)
    end

    it "範囲内の値はそのまま使う" do
      expect(described_class.per_page("5")).to eq(5)
      expect(described_class.per_page(50)).to eq(50)
    end
  end

  describe ".page_number" do
    it "未指定・0 以下・非数値は 1 ページ目" do
      expect(described_class.page_number(nil)).to eq(1)
      expect(described_class.page_number("0")).to eq(1)
      expect(described_class.page_number("-2")).to eq(1)
      expect(described_class.page_number("abc")).to eq(1)
    end

    it "正の値はそのまま使う" do
      expect(described_class.page_number("3")).to eq(3)
    end
  end

  describe "#search_params" do
    subject(:query) do
      described_class.new(community: community, query: query_value, category: category_value,
                          sort: sort, page: page, per_page: limit)
    end

    let(:query_value) { "  " }
    let(:category_value) { nil }
    let(:sort) { nil }
    let(:page) { nil }
    let(:limit) { nil }

    it "HomepageController#find_listings と同じキーをそろえる" do
      expect(query.search_params.keys).to match_array(
        %i[categories listing_shape_ids price_cents keywords fields per_page page
           price_min price_max locale include_closed sort sort_by]
      )
    end

    it "空の query は keywords: nil（= 全件検索）" do
      expect(query.search_params[:keywords]).to be_nil
    end

    context "query があるとき" do
      let(:query_value) { "  校正  " }

      it "前後の空白を落として keywords に渡す" do
        expect(query.search_params[:keywords]).to eq("校正")
      end
    end

    it "並び順は sort_by に渡し、検索エンジン用の sort は使わない" do
      expect(query.search_params[:sort_by]).to eq("popular")
      expect(query.search_params[:sort]).to be_nil
    end

    it "既定はページ 1・20 件、閉じた出品は含めない" do
      expect(query.search_params).to include(page: 1, per_page: 20, include_closed: false)
    end

    context "カテゴリ指定があるとき" do
      let(:category_value) { category.url }

      it "配下のサブカテゴリを含む id 配列を渡す" do
        expect(query.search_params[:categories]).to eq(category.own_and_subcategory_ids)
      end
    end

    context "存在しないカテゴリ指定のとき" do
      let(:category_value) { "no-such-category" }

      it "/browse と同じく絞り込まない（nil）" do
        expect(query.search_params[:categories]).to be_nil
      end
    end
  end

  describe "#call" do
    it "DB フォールバック経由でも一覧の並び順の id を返す" do
      oldest = create_listing(title: "oldest", sort_date: 3.days.ago)
      newest = create_listing(title: "newest", sort_date: 1.day.ago)

      result = described_class.new(community: community, per_page: 50).call

      expect(result.success).to be(true)
      expect(result.data.listing_ids).to eq([newest.id, oldest.id])
      expect(result.data.total_entries).to eq(2)
    end

    it "別のマーケットプレイスの出品は返さない" do
      other_community = FactoryBot.create(:community)
      other_listing = FactoryBot.create(:listing, community_id: other_community.id,
                                                  author: person, title: "other")
      own_listing = create_listing(title: "own")

      result = described_class.new(community: community, per_page: 50).call

      expect(result.data.listing_ids).to eq([own_listing.id])
      expect(result.data.listing_ids).not_to include(other_listing.id)
    end
  end
end
