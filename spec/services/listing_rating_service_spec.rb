# frozen_string_literal: true

require "rails_helper"

# Issue #106 Phase 2a: 出品（ペルソナ）評価の集計。
#
# `avg_rating` の尺度は 1〜5（既存の手動値 4.5 等と同じ）。`testimonials.grade`
# （0..1）の平均を ×4 + 1 して小数第1位に丸める。0 件なら 0.0（＝評価なし）。
#
# 評価行は insert_all で作る。ここで見たいのは集計式だけであり、
# Testimonial の after_commit（再計算のトリガ）は別 spec で検証するため。
RSpec.describe ListingRatingService, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id, author: author,
                                avg_rating: 0.0, reviews_count: 0)
  end

  def insert_reviews(grades, listing_id:, blocked: false)
    now = Time.current
    Testimonial.insert_all(
      grades.each_with_index.map do |grade, index|
        {
          listing_id: listing_id,
          author_id: "reviewer-#{SecureRandom.hex(4)}-#{index}",
          receiver_id: author.id,
          grade: grade,
          blocked: blocked,
          created_at: now,
          updated_at: now
        }
      end
    )
  end

  # コールバックや直前の検証で値が動いていても、再計算前を既知の状態にする。
  def reset_listing_values
    listing.update_columns(avg_rating: 0.0, reviews_count: 0)
  end

  def recalculate
    described_class.recalculate!(listing)
    listing.reload
  end

  describe ".recalculate!" do
    it "レビューが0件なら avg_rating 0.0 / reviews_count 0 にする" do
      recalculate

      expect(listing.avg_rating).to eq(0.0)
      expect(listing.reviews_count).to eq(0)
    end

    it "4★1件（grade 0.75）は avg_rating 4.0 / reviews_count 1" do
      insert_reviews([0.75], listing_id: listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(4.0)
      expect(listing.reviews_count).to eq(1)
    end

    it "1★1件（grade 0.0）は avg_rating 1.0" do
      insert_reviews([0.0], listing_id: listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(1.0)
    end

    it "5★1件（grade 1.0）は avg_rating 5.0" do
      insert_reviews([1.0], listing_id: listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(5.0)
    end

    it "複数件は grade の平均から換算する（0.75/0.5/1.0 → 4.0, 3件）" do
      insert_reviews([0.75, 0.5, 1.0], listing_id: listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(4.0)
      expect(listing.reviews_count).to eq(3)
    end

    it "小数第1位で四捨五入する（0.875 → 4.5）" do
      insert_reviews([1.0, 0.75], listing_id: listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(4.5)
    end

    it "四捨五入の境界でも 1 桁に丸める（0.375 → 2.5）" do
      insert_reviews([0.5, 0.25], listing_id: listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(2.5)
      expect(listing.reviews_count).to eq(2)
    end

    it "blocked のレビューは件数にも平均にも含めない" do
      insert_reviews([0.75], listing_id: listing.id)
      insert_reviews([0.0], listing_id: listing.id, blocked: true)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(4.0)
      expect(listing.reviews_count).to eq(1)
    end

    it "grade が NULL の行は集計対象から外す" do
      insert_reviews([0.75], listing_id: listing.id)
      insert_reviews([nil], listing_id: listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(4.0)
      expect(listing.reviews_count).to eq(1)
    end

    it "取引レビュー（listing_id が NULL）は集計に含めない" do
      insert_reviews([1.0, 0.75], listing_id: nil)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(0.0)
      expect(listing.reviews_count).to eq(0)
    end

    it "他の出品のレビューを混ぜない" do
      other_listing = FactoryBot.create(:listing, community_id: community.id, author: author)
      insert_reviews([0.75], listing_id: listing.id)
      insert_reviews([1.0, 1.0], listing_id: other_listing.id)
      reset_listing_values

      recalculate

      expect(listing.avg_rating).to eq(4.0)
      expect(listing.reviews_count).to eq(1)
    end

    it "出品が存在しなければ nil を返す（例外にしない）" do
      expect(described_class.recalculate!(listing.id + 1_000_000)).to be_nil
    end

    it "出品オブジェクトでも ID でも同じように再計算する" do
      insert_reviews([0.5], listing_id: listing.id)
      reset_listing_values

      described_class.recalculate!(listing.id)
      expect(listing.reload.avg_rating).to eq(3.0)
    end

    it "既に同じ値なら UPDATE しない（冪等）" do
      insert_reviews([0.75], listing_id: listing.id)
      recalculate

      updates = count_listing_updates { described_class.recalculate!(listing.id) }

      expect(updates).to eq(0)
      expect(listing.reload.avg_rating).to eq(4.0)
    end
  end

  describe ".expected_attributes" do
    it "DB を書き換えずに集計値だけを返す（rake のドライラン用）" do
      insert_reviews([0.75, 0.5], listing_id: listing.id)
      reset_listing_values

      attributes = described_class.expected_attributes(listing)

      expect(attributes).to eq({ reviews_count: 2, avg_rating: 3.5 })
      expect(listing.reload.avg_rating).to eq(0.0)
      expect(listing.reviews_count).to eq(0)
    end
  end

  # listings への UPDATE 文の数を数える。
  def count_listing_updates
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      count += 1 if sql.start_with?("UPDATE") && sql.include?("`listings`")
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
