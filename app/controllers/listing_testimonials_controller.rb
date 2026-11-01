# frozen_string_literal: true

# Issue #106 Phase 1: 出品（ペルソナ）単位の評価投稿。
#
# 既存の Testimonial を流用するが、取引コミュニケーションに紐づく
# TestimonialsController とは入口（根拠）が違うためコントローラを分ける。
# 取引レビューの既存フローには触らない。
#
# POST /:locale/listings/:listing_id/testimonials
# 投稿できるのは、その出品の ChatSession で AI 応答を受け取った利用者
# （出品者本人を除く・1人1出品1回）。判定は Policy::ListingReviewPolicy。
class ListingTestimonialsController < ApplicationController

  before_action do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_give_feedback")
  end

  before_action :find_listing
  before_action :ensure_reviewable

  def create
    if save_testimonial
      flash[:notice] = t("layouts.notifications.listing_review_thanks")
    else
      flash[:error] = t("layouts.notifications.listing_review_failed")
    end
    redirect_to listing_path(@listing)
  end

  private

  def find_listing
    @listing = Listing.find_by(id: params[:listing_id], community_id: @current_community.id)
    return if @listing

    flash[:error] = t("layouts.notifications.you_are_not_authorized_to_view_this_content")
    redirect_to search_path
  end

  def ensure_reviewable
    return unless @listing

    policy = Policy::ListingReviewPolicy.new(@listing, @current_user)
    return if policy.can_create?

    flash[:error] = if policy.author?
                      t("layouts.notifications.listing_review_own_listing")
                    elsif policy.already_reviewed?
                      t("layouts.notifications.listing_review_already_given")
                    else
                      t("layouts.notifications.listing_review_not_eligible")
                    end
    redirect_to listing_path(@listing)
  end

  # 星 1〜5 を grade(0..1) に換算して保存する。
  # 同時投稿で DB の unique index に弾かれた場合も「評価済み」と同じ扱いにする。
  def save_testimonial
    Testimonial.new(testimonial_attributes).save
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def testimonial_attributes
    permitted = params.require(:testimonial).permit(:stars, :text)
    {
      listing_id: @listing.id,
      author_id: @current_user.id,
      receiver_id: @listing.author_id,
      grade: Testimonial.grade_from_stars(permitted[:stars]),
      text: permitted[:text]
    }
  end
end
