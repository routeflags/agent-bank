# frozen_string_literal: true

require 'spec_helper'

# Issue #151: レビュー（ペルソナ評価）への「いいね」。
describe TestimonialLike, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:seller) { FactoryBot.create(:person, community_id: community.id) }
  let(:reviewer) { FactoryBot.create(:person, community_id: community.id) }
  let(:liker) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id,
                                listing_shape_id: 123,
                                author: seller)
  end
  let(:testimonial) do
    Testimonial.create!(listing: listing, author: reviewer, receiver: seller,
                        grade: 1.0, text: 'よかった')
  end

  it '同じ人が同じレビューに 2 回いいねできない' do
    described_class.create!(testimonial: testimonial, person: liker)
    duplicate = described_class.new(testimonial: testimonial, person: liker)

    expect(duplicate).not_to be_valid
    expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it '別の利用者なら同じレビューにいいねできる' do
    other = FactoryBot.create(:person, community_id: community.id)
    described_class.create!(testimonial: testimonial, person: liker)

    expect { described_class.create!(testimonial: testimonial, person: other) }
      .to change(described_class, :count).by(1)
    expect(testimonial.reload.likes_count).to eq(2)
  end

  it 'いいねの作成・削除で testimonials.likes_count が増減する（counter cache）' do
    expect(testimonial.likes_count).to eq(0)

    like = described_class.create!(testimonial: testimonial, person: liker)
    expect(testimonial.reload.likes_count).to eq(1)

    like.destroy
    expect(testimonial.reload.likes_count).to eq(0)
  end

  it 'レビューを削除すると、そのいいねも消える（dependent: :destroy）' do
    other = FactoryBot.create(:person, community_id: community.id)
    described_class.create!(testimonial: testimonial, person: liker)
    described_class.create!(testimonial: testimonial, person: other)

    expect { testimonial.destroy }.to change(described_class, :count).by(-2)
  end
end
