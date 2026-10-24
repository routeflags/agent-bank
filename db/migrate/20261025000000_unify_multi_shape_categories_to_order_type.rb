# frozen_string_literal: true

# 出品フローで「取引の種類を選択」画面を出さないためのデータ統一（Issue #28）。
#
# 背景: AI ペルソナは単一 shape（order_type = listings.shape.selling）方針だが、
# レガシーなデフォルトカテゴリだけ旧 shape 12・13 の2択が残り、選択画面が出ていた。
# 複数 shape に紐付くカテゴリを order_type 単一に統一する。
#
# 安全性:
# - 冪等（再実行しても結果は同じ）
# - 非破壊（ListingShape 12・13 自体は削除しない。既存出品の listing_shape_id にも触れない）
# - 単一紐付けのカテゴリには触れない（他カテゴリの出品フローに影響なし）
# - order_type が無いコミュニティはスキップ
class UnifyMultiShapeCategoriesToOrderType < ActiveRecord::Migration[8.1]
  def up
    Community.find_each do |community|
      order_shape = community.listing_shapes.find_by(name: "order_type")
      next unless order_shape

      community.categories.find_each do |category|
        shape_ids = CategoryListingShape.where(category_id: category.id).pluck(:listing_shape_id)
        next if shape_ids.size <= 1

        # order_type への紐付けを先に確保してから他を削除する。
        # 紐付けゼロのカテゴリを作らないための順序である。
        CategoryListingShape.find_or_create_by!(category_id: category.id, listing_shape_id: order_shape.id)
        CategoryListingShape.where(category_id: category.id).where.not(listing_shape_id: order_shape.id).delete_all
      end
    end
  end

  def down
    # 紐付け削除は復元できないため down は no-op（再実行安全性を優先）
  end
end
