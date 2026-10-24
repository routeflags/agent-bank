# frozen_string_literal: true

require 'rails_helper'

# 出品フロー形状統一の回帰 spec（Issue #28・#29）。
#
# #28: カテゴリ 22 の複数 shape 紐付けを order_type 単一に統一する
#      マイグレーションが冪等・非破壊であること。
# #29: new.haml に取引種類の選択済み表示が出ないこと。
RSpec.describe "出品フロー形状統一", type: :model do
  before(:all) do
    require Rails.root.join("db/migrate/20261025000000_unify_multi_shape_categories_to_order_type.rb")
  end

  def run_unify!
    UnifyMultiShapeCategoriesToOrderType.new.up
  end

  let(:community) { FactoryBot.create(:community) }
  let(:process_none) { FactoryBot.create(:transaction_process, community_id: community.id, process: "none") }
  let!(:order_shape) do
    FactoryBot.create(:listing_shape, community_id: community.id,
                      transaction_process_id: process_none.id, name: "order_type")
  end

  describe "マイグレーション" do
    it "複数紐付けカテゴリ（レガシー12・13相当）を order_type 単一に統一する" do
      legacy_a = FactoryBot.create(:listing_shape, community_id: community.id,
                                    transaction_process_id: process_none.id, name: "legacy-a")
      legacy_b = FactoryBot.create(:listing_shape, community_id: community.id,
                                    transaction_process_id: process_none.id, name: "legacy-b")
      category = FactoryBot.create(:category, community: community)
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: legacy_a.id)
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: legacy_b.id)

      run_unify!

      expect(CategoryListingShape.where(category_id: category.id).pluck(:listing_shape_id))
        .to eq([order_shape.id])
    end

    it "shape 自体は削除しない（非破壊）" do
      legacy = FactoryBot.create(:listing_shape, community_id: community.id,
                                  transaction_process_id: process_none.id, name: "legacy-keep")
      category = FactoryBot.create(:category, community: community)
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: legacy.id)
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: order_shape.id)

      expect { run_unify! }.not_to(change { ListingShape.where(id: legacy.id).count })
      expect(ListingShape.where(id: legacy.id).count).to eq(1)
    end

    it "単一紐付けカテゴリには触れない（他カテゴリのフローに影響なし）" do
      single_shape = FactoryBot.create(:listing_shape, community_id: community.id,
                                        transaction_process_id: process_none.id, name: "single")
      category = FactoryBot.create(:category, community: community)
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: single_shape.id)

      run_unify!

      expect(CategoryListingShape.where(category_id: category.id).pluck(:listing_shape_id))
        .to eq([single_shape.id])
    end

    it "冪等である（2回実行しても結果は同じ）" do
      legacy = FactoryBot.create(:listing_shape, community_id: community.id,
                                  transaction_process_id: process_none.id, name: "legacy-idem")
      category = FactoryBot.create(:category, community: community)
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: legacy.id)
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: order_shape.id)

      run_unify!
      first = CategoryListingShape.where(category_id: category.id).pluck(:listing_shape_id)
      run_unify!
      second = CategoryListingShape.where(category_id: category.id).pluck(:listing_shape_id)
      expect(second).to eq(first)
      expect(second).to eq([order_shape.id])
    end
  end

  describe "new.haml（#29）" do
    let(:template) { File.read(Rails.root.join("app/views/listings/new.haml")) }

    it "取引種類の選択済み表示ブロックが無い" do
      expect(template).not_to include('selected-group{:name => "listing_shape"}')
      expect(template).not_to include("selected_transaction_type")
      # option-group は将来の複数 shape への保険として残す
      expect(template).to include('.option-group')
    end

    it "カテゴリ・サブカテゴリの選択済み表示は残る" do
      expect(template).to include('"category"')
      expect(template).to include('"subcategory"')
    end
  end
end
