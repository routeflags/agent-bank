# frozen_string_literal: true

require 'spec_helper'

# Issue #106 Phase 1: 出品（ペルソナ）評価の投稿条件。
#
# 投稿できるのは、その出品の ChatSession で AI 応答を受け取った利用者
# （出品者本人を除く・1人1出品1回）。
describe Policy::ListingReviewPolicy do
  let(:community) { FactoryBot.create(:community) }
  let(:seller) { FactoryBot.create(:person, community_id: community.id) }
  let(:reviewer) { FactoryBot.create(:person, community_id: community.id) }
  let(:stranger) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id,
                                listing_shape_id: 123,
                                author: seller)
  end

  def session_with_reply(person, target_listing = listing)
    session = FactoryBot.create(:chat_session, listing: target_listing, person_id: person.id)
    FactoryBot.create(:chat_message, chat_session: session, role: 'assistant', seq: 2)
    session
  end

  def session_without_reply(person, target_listing = listing)
    session = FactoryBot.create(:chat_session, listing: target_listing, person_id: person.id)
    FactoryBot.create(:chat_message, chat_session: session, role: 'user', seq: 1)
    session
  end

  def write_review(person, target_listing = listing)
    Testimonial.create!(listing: target_listing, author: person, receiver: seller,
                        grade: 0.5, text: 'ok')
  end

  describe '#can_create?' do
    it 'AI 応答を受け取った利用者は投稿できる' do
      session_with_reply(reviewer)

      policy = described_class.new(listing, reviewer)
      expect(policy.can_create?).to be(true)
      expect(policy.used_persona?).to be(true)
      expect(policy.author?).to be(false)
      expect(policy.already_reviewed?).to be(false)
    end

    it '出品者本人は投稿できない（AI 応答があっても）' do
      session_with_reply(seller)

      policy = described_class.new(listing, seller)
      expect(policy.can_create?).to be(false)
      expect(policy.author?).to be(true)
    end

    it 'user メッセージだけのセッションでは投稿できない' do
      session_without_reply(reviewer)

      policy = described_class.new(listing, reviewer)
      expect(policy.can_create?).to be(false)
      expect(policy.used_persona?).to be(false)
    end

    it 'チャット履歴が無ければ投稿できない' do
      expect(described_class.new(listing, stranger).can_create?).to be(false)
    end

    it '別の出品の AI 応答では投稿できない' do
      other_listing = FactoryBot.create(:listing, community_id: community.id,
                                                  listing_shape_id: 123,
                                                  author: seller)
      session_with_reply(reviewer, other_listing)

      expect(described_class.new(listing, reviewer).can_create?).to be(false)
    end

    it '他人の AI 応答セッションでは投稿できない' do
      session_with_reply(stranger)
      session_without_reply(reviewer)

      expect(described_class.new(listing, reviewer).can_create?).to be(false)
    end

    it '評価済みなら投稿できない' do
      session_with_reply(reviewer)
      write_review(reviewer)

      policy = described_class.new(listing, reviewer)
      expect(policy.can_create?).to be(false)
      expect(policy.already_reviewed?).to be(true)
    end

    it '未ログイン（nil）でも例外にならず false を返す' do
      policy = described_class.new(listing, nil)

      expect(policy.can_create?).to be(false)
      expect(policy.already_reviewed?).to be(false)
      expect(policy.used_persona?).to be(false)
      expect(policy.author?).to be(false)
    end
  end
end
