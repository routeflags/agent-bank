# frozen_string_literal: true

require 'spec_helper'

# Issue #106 Phase 1: 既存 Testimonial を流用した出品（ペルソナ）評価。
describe Testimonial, 'ペルソナ評価', type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:seller) { FactoryBot.create(:person, community_id: community.id) }
  let(:reviewer) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id,
                                listing_shape_id: 123,
                                author: seller)
  end

  def build_review(attrs = {})
    described_class.new({
      listing: listing,
      author: reviewer,
      receiver: seller,
      grade: 0.5,
      text: 'よかった'
    }.merge(attrs))
  end

  describe '.grade_from_stars' do
    it '星 1〜5 を grade 0..1 に換算する（1→0.0, 5→1.0）' do
      expect(described_class.grade_from_stars(1)).to eq(0.0)
      expect(described_class.grade_from_stars(2)).to eq(0.25)
      expect(described_class.grade_from_stars(3)).to eq(0.5)
      expect(described_class.grade_from_stars(4)).to eq(0.75)
      expect(described_class.grade_from_stars(5)).to eq(1.0)
    end

    it 'フォームから来る文字列の星も受け付ける' do
      expect(described_class.grade_from_stars('4')).to eq(0.75)
    end

    it '範囲外・非数値は nil を返す（grade の inclusion 検証で弾く）' do
      [nil, '', 'abc', 0, 6, -1].each do |stars|
        expect(described_class.grade_from_stars(stars)).to be_nil
      end
    end

    it '換算した grade は既存の displayed_grade と整合する' do
      (1..5).each do |stars|
        testimonial = described_class.new(grade: described_class.grade_from_stars(stars))
        expect(testimonial.displayed_grade).to eq(stars)
      end
    end
  end

  describe '出品レビューの検証' do
    it '条件を満たす出品レビューは保存できる' do
      expect(build_review.save).to be(true)
    end

    it '本文は任意（空文字でも nil でも保存できる）' do
      expect(build_review(text: '').save).to be(true)

      another_reviewer = FactoryBot.create(:person, community_id: community.id)
      expect(build_review(author: another_reviewer, text: nil).save).to be(true)
    end

    it '本文は 1000 文字まで。超えると保存できない' do
      expect(build_review(text: 'あ' * described_class::TEXT_MAX_LENGTH).save).to be(true)

      too_long = build_review(text: 'あ' * (described_class::TEXT_MAX_LENGTH + 1))
      expect(too_long.save).to be(false)
      expect(too_long.errors[:text]).to be_present
    end

    it '同じ人の同じ出品への 2 回目は保存できない' do
      expect(build_review.save).to be(true)

      second = build_review
      expect(second.save).to be(false)
      expect(second.errors[:author_id]).to be_present
    end

    it 'DB の unique index も二重投稿を拒否する（検証を飛ばした場合）' do
      expect(build_review.save).to be(true)

      duplicate = build_review
      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'grade が欠落・範囲外なら保存できない' do
      expect(build_review(grade: nil).save).to be(false)
      expect(build_review(grade: 1.25).save).to be(false)
    end

    it '同じ人でも別の出品なら評価できる' do
      other_listing = FactoryBot.create(:listing, community_id: community.id,
                                                  listing_shape_id: 123,
                                                  author: seller)
      expect(build_review.save).to be(true)
      expect(build_review(listing: other_listing).save).to be(true)
    end

    it '既存の取引レビュー（listing_id なし）は本文長・重複の検証対象外' do
      long_text_review = described_class.new(
        author: reviewer, receiver: seller, grade: 0.5,
        text: 'あ' * (described_class::TEXT_MAX_LENGTH + 1)
      )
      expect(long_text_review.save).to be(true)

      second = described_class.new(author: reviewer, receiver: seller, grade: 0.5, text: 'ok')
      expect(second.save).to be(true)
    end
  end

  describe 'ChatSession.with_assistant_message' do
    it 'AI 応答（assistant）があるセッションだけを返す' do
      with_reply = FactoryBot.create(:chat_session, listing: listing, person_id: reviewer.id)
      FactoryBot.create(:chat_message, chat_session: with_reply, role: 'assistant', seq: 2)

      without_reply = FactoryBot.create(:chat_session, listing: listing, person_id: seller.id)
      FactoryBot.create(:chat_message, chat_session: without_reply, role: 'user', seq: 1)

      expect(ChatSession.with_assistant_message).to include(with_reply)
      expect(ChatSession.with_assistant_message).not_to include(without_reply)
    end

    it '同じセッションに assistant が複数あっても重複しない' do
      session = FactoryBot.create(:chat_session, listing: listing, person_id: reviewer.id)
      2.times { |i| FactoryBot.create(:chat_message, chat_session: session, role: 'assistant', seq: i + 1) }

      expect(ChatSession.with_assistant_message.to_a).to eq([session])
    end
  end
end
