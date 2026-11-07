# frozen_string_literal: true

# == Schema Information
#
# Table name: testimonial_likes
#
#  id             :bigint           not null, primary key
#  testimonial_id :integer          not null
#  person_id      :string(22)       not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_testimonial_likes_on_person_id                     (person_id)
#  index_testimonial_likes_on_testimonial_id_and_person_id  (testimonial_id,person_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (testimonial_id => testimonials.id)
#

# Issue #151: レビュー（ペルソナ評価）への「いいね」。
#
# 1人1レビュー1回。同じ人が二重に押しても行は増えない（unique index と
# `validates :person_id, uniqueness:` の両方で止める）。
#
# `likes_count` は counter cache。レビューの `grade` には触らないため、
# 出品の `avg_rating` / `reviews_count` は変化しない。
class TestimonialLike < ApplicationRecord
  belongs_to :testimonial, counter_cache: :likes_count
  belongs_to :person

  # DB の unique index と同じ条件。同時押しはここを抜けても DB が弾くので、
  # 呼び出し側は両方の失敗を「いいね済み」として扱う。
  validates :person_id, uniqueness: { scope: :testimonial_id }
end
