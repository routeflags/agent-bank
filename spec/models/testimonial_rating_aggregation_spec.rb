# frozen_string_literal: true

require "rails_helper"

# Issue #106 Phase 2a: 評価の増減に伴う集計カラムの更新。
#
# Rails 8.1 + DatabaseCleaner（:transaction）では after_commit が発火するため
# （実測）、特別なタグは付けずに検証できる。
RSpec.describe "Testimonial の評価集計連動", type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:reviewer) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id, author: author,
                                avg_rating: 0.0, reviews_count: 0)
  end

  def create_review(grade:, listing: self.listing, reviewer: self.reviewer)
    Testimonial.create!(
      listing_id: listing&.id,
      author_id: reviewer.id,
      receiver_id: author.id,
      grade: grade
    )
  end

  it "出品レビューの作成で avg_rating / reviews_count が更新される" do
    create_review(grade: 0.75)

    expect(listing.reload.avg_rating).to eq(4.0)
    expect(listing.reviews_count).to eq(1)
  end

  it "2件目以降も件数と平均が積み上がる" do
    create_review(grade: 0.75)
    other_reviewer = FactoryBot.create(:person, community_id: community.id)
    create_review(grade: 1.0, reviewer: other_reviewer)

    expect(listing.reload.avg_rating).to eq(4.5)
    expect(listing.reviews_count).to eq(2)
  end

  it "削除で集計が戻る（0件なら 0.0）" do
    review = create_review(grade: 0.75)
    expect(listing.reload.reviews_count).to eq(1)

    review.destroy

    expect(listing.reload.avg_rating).to eq(0.0)
    expect(listing.reviews_count).to eq(0)
  end

  it "blocked にすると集計から外れる" do
    review = create_review(grade: 0.75)

    review.update!(blocked: true)

    expect(listing.reload.avg_rating).to eq(0.0)
    expect(listing.reviews_count).to eq(0)
  end

  it "紐付け先を変えると移動元と移動先の両方が再計算される" do
    other_listing = FactoryBot.create(:listing, community_id: community.id, author: author)
    review = create_review(grade: 1.0)
    expect(listing.reload.reviews_count).to eq(1)

    review.update!(listing_id: other_listing.id)

    expect(listing.reload.reviews_count).to eq(0)
    expect(listing.avg_rating).to eq(0.0)
    expect(other_listing.reload.reviews_count).to eq(1)
    expect(other_listing.avg_rating).to eq(5.0)
  end

  it "取引レビュー（listing_id が NULL）では集計を触らない" do
    listing.update_columns(avg_rating: 3.3, reviews_count: 7)

    review = create_review(grade: 1.0, listing: nil)

    expect(listing.reload.avg_rating).to eq(3.3)
    expect(listing.reviews_count).to eq(7)

    review.destroy

    expect(listing.reload.avg_rating).to eq(3.3)
    expect(listing.reviews_count).to eq(7)
  end

  it "再計算が失敗してもレビュー投稿は成功し、ログに残る" do
    allow(ListingRatingService).to receive(:recalculate!).and_raise(StandardError, "boom")
    expect(Rails.logger).to receive(:error).with(/ListingRatingService.*boom/)

    review = nil
    expect { review = create_review(grade: 0.75) }.not_to raise_error

    expect(review.persisted?).to be(true)
    expect(Testimonial.where(listing_id: listing.id).count).to eq(1)
  end
end
