# frozen_string_literal: true

# 出品（ペルソナ）単位の評価を投稿できるかを判定する（Issue #106 Phase 1）。
#
# 投稿できるのは次のすべてを満たす利用者（1人1出品1回）:
# - ログインしている
# - 出品者本人ではない
# - その出品の ChatSession で AI 応答（assistant メッセージ）を受け取っている
# - その出品をまだ評価していない
#
# コミュニティへの所属は ApplicationController#ensure_user_belongs_to_community が
# 全リクエストで担保しているため、ここでは判定しない。
class Policy::ListingReviewPolicy
  attr_reader :listing, :user

  def initialize(listing, user)
    @listing = listing
    @user = user
  end

  def can_create?
    valid_target? && !author? && used_persona? && !already_reviewed?
  end

  def author?
    return false unless valid_target?

    listing.author_id == user.id
  end

  # その出品で AI 応答を受け取ったセッションを持っているか。
  # 判定は本人のセッション（chat_sessions.person_id = 利用者）に限る。
  def used_persona?
    return false unless valid_target?

    ChatSession
      .where(listing_id: listing.id, person_id: user.id)
      .with_assistant_message
      .exists?
  end

  def already_reviewed?
    return false unless valid_target?

    Testimonial.where(listing_id: listing.id, author_id: user.id).exists?
  end

  private

  def valid_target?
    listing.present? && user.present?
  end
end
