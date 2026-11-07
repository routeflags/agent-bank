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

  # レビューに「いいね」できるか（Issue #151）。
  #
  # 条件はここ 1 か所だけに置く。ビュー（ボタンを出すか）と
  # `TestimonialLikesController`（403 を返すか）の両方がこのメソッドを使う。
  # 未ログインは false になり、ビューはログイン導線を出す。
  def can_like?(testimonial)
    return false if testimonial.blank? || !valid_target?

    !own_review?(testimonial)
  end

  # そのレビューの投稿者本人か。自分のレビューにはいいねできない（Issue #151）。
  # `author?`（出品者本人か）とは別の判定。
  def own_review?(testimonial)
    return false if testimonial.blank? || user.blank?

    testimonial.author_id == user.id
  end

  private

  def valid_target?
    listing.present? && user.present?
  end
end
