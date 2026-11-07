# frozen_string_literal: true

# Issue #151: レビュー（ペルソナ評価）への「いいね」。
#
# POST   /:locale/listings/:listing_id/testimonials/:testimonial_id/like
# DELETE /:locale/listings/:listing_id/testimonials/:testimonial_id/like
#
# トグル 1 本ではなく create / destroy の 2 経路。二重押し・リトライでは
# どちらも 200 を返し、件数だけが正しければよい（409 にしない）。
# CSRF は通常の Rails の保護に乗せる（`skip_before_action` しない）。
#
# 判定（自分のレビューか・ログインしているか）は `Policy::ListingReviewPolicy`
# に集約し、ビューのボタン出し分けと同じメソッドを使う。
class TestimonialLikesController < ApplicationController
  before_action :ensure_authenticated
  before_action :find_testimonial
  before_action :ensure_likeable

  def create
    like!
    render json: like_state(liked: true)
  end

  def destroy
    unlike!
    render json: like_state(liked: false)
  end

  private

  # Ajax は JSON（401 + login_url）を返す。素の HTML 遷移はログイン画面へ。
  # リダイレクトの HTML を返すと、 fetch 側は 200 の HTML を受け取って壊れる。
  def ensure_authenticated
    return if logged_in?

    if request.format.json?
      render json: { error: "unauthorized", login_url: login_path }, status: :unauthorized
    else
      ensure_logged_in(t("layouts.notifications.you_must_log_in_to_view_this_content"))
    end
  end

  # レビューは URL の出品に属するものだけを対象にする。別の出品の ID を
  # 混ぜたリクエストや存在しない ID は 404。
  def find_testimonial
    @listing = Listing.find_by(id: params[:listing_id], community_id: @current_community.id)
    @testimonial = @listing && Testimonial.find_by(id: params[:testimonial_id], listing_id: @listing.id)
    return if @testimonial

    render_error(:not_found, "not_found")
  end

  def ensure_likeable
    return if Policy::ListingReviewPolicy.new(@listing, @current_user).can_like?(@testimonial)

    render_error(:forbidden, "forbidden")
  end

  # 同じ人が二重に押しても行は増やさない（冪等）。
  #
  # `find_or_create_by` は内部で `create_or_find_by` を使うため、SELECT と
  # INSERT の間で同じ人が押した場合（unique index 違反）も既存行に落ちる。
  def like!
    TestimonialLike.find_or_create_by(testimonial_id: @testimonial.id, person_id: @current_user.id)
  end

  def unlike!
    TestimonialLike.where(testimonial_id: @testimonial.id, person_id: @current_user.id).destroy_all
  end

  # 件数は counter cache（testimonials.likes_count）を DB から読み直す。
  # インスタンスを reload するとレビュー本文（TEXT）まで引き直すため、
  # 必要な 1 列だけを取る。
  def like_state(liked:)
    { liked: liked, likes_count: Testimonial.where(id: @testimonial.id).pick(:likes_count).to_i }
  end

  def render_error(status, code)
    if request.format.json?
      render json: { error: code }, status: status
    else
      head status
    end
  end
end
