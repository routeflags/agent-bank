# frozen_string_literal: true

# Issue #106 Phase 1: ペルソナ（出品）単位の評価を既存 Testimonial で表現するための
# 紐付けカラム。既存の取引レビューは listing_id = NULL のまま動く（データ移行不要。
# 2026-11 時点の開発 DB で testimonials は 0 件）。
#
# (listing_id, author_id) の unique index で「1人1出品1回」を DB でも担保する。
# MySQL の UNIQUE は NULL を重複と見なさないため、listing_id が NULL の取引レビュー
# （同一人物が複数件書ける）には影響しない。
class AddListingIdToTestimonials < ActiveRecord::Migration[8.1]
  def change
    change_table :testimonials, bulk: true do |t|
      t.integer :listing_id
      t.index :listing_id
      t.index [:listing_id, :author_id],
              unique: true,
              name: "index_testimonials_on_listing_id_and_author_id"
    end
  end
end
