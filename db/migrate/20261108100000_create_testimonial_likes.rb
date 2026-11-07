# frozen_string_literal: true

# Issue #151: レビュー（Testimonial）への「いいね」。
#
# 「1人1レビュー1回」は `[testimonial_id, person_id]` の unique index で担保する。
# `testimonials` 側の `[listing_id, author_id]` UNIQUE は「1人1出品1レビュー」の
# ための別の制約なので流用しない（1件のレビューに複数人がいいねできる）。
#
# 型は参照先に合わせる: `testimonials.id` は int、`people.id` は varchar(22)。
# `t.references`（bigint を作る）は使わない。`people` への外部キーは
# `chat_sessions` と同じく張らない（人物の削除を阻むため）。
class CreateTestimonialLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :testimonial_likes do |t|
      t.integer :testimonial_id, null: false
      t.string :person_id, limit: 22, null: false

      t.timestamps

      # 1人1レビュー1回。同時押しはこの unique index が止める。
      t.index [:testimonial_id, :person_id], unique: true
      t.index :person_id
    end

    add_foreign_key :testimonial_likes, :testimonials
  end
end
