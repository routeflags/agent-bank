# == Schema Information
#
# Table name: testimonials
#
#  id               :integer          not null, primary key
#  grade            :float(24)
#  text             :text(65535)
#  author_id        :string(255)
#  participation_id :integer
#  transaction_id   :integer
#  created_at       :datetime
#  updated_at       :datetime
#  receiver_id      :string(255)
#  blocked          :boolean          default(FALSE)
#  listing_id       :integer
#
# Indexes
#
#  index_testimonials_on_author_id                    (author_id)
#  index_testimonials_on_listing_id                   (listing_id)
#  index_testimonials_on_listing_id_and_author_id     (listing_id,author_id) UNIQUE
#  index_testimonials_on_receiver_id                  (receiver_id)
#  index_testimonials_on_transaction_id               (transaction_id)
#

class Testimonial < ApplicationRecord

  # 評価本文の上限（Issue #106 Phase 1）。出品レビューにのみ適用する。
  TEXT_MAX_LENGTH = 1000

  # UI の星 1〜5。grade(0..1) と相互変換する。
  STARS = (1..5)

  belongs_to :author, :class_name => "Person"
  belongs_to :receiver, :class_name => "Person"
  belongs_to :tx, class_name: "Transaction", foreign_key: "transaction_id", inverse_of: :testimonials
  # 出品（ペルソナ）単位の評価（Issue #106 Phase 1）。取引レビューは transaction_id
  # で紐づき listing_id は NULL のままなので optional。
  belongs_to :listing, optional: true

  validates_inclusion_of :grade, :in => 0..1, :allow_nil => false

  # 以下は出品レビュー（listing_id あり）に限定した検証。既存の取引レビュー
  # （listing_id は NULL）の入力条件を締め付けないため if で切り替える。
  validates :text, length: { maximum: TEXT_MAX_LENGTH }, if: :listing_review?
  validates :author_id, uniqueness: { scope: :listing_id }, if: :listing_review?

  # 出品レビューが増減・変更されたら、出品の集計カラム（avg_rating /
  # reviews_count）を同期する（Issue #106 Phase 2a）。取引レビュー
  # （listing_id が NULL）は何も変えない。
  after_commit :refresh_listing_rating, on: [:create, :update, :destroy]

  scope :positive, -> { where("grade >= 0.5") }
  scope :negative, -> { where("grade < 0.5") }
  scope :id_order, -> { order("id DESC") }
  scope :non_blocked, -> { where(blocked: false) }
  scope :blocked, -> { where(blocked: true) }

  scope :by_community, -> (community) {
    joins(:tx).merge(Transaction.by_community(community.id).exist)
  }

  scope :with_tx_subquery, -> { where("testimonials.transaction_id = transactions.id") }
  scope :with_tx_author, -> { with_tx_subquery.where("testimonials.author_id = transactions.listing_author_id") }
  scope :with_tx_starter, -> { with_tx_subquery.where("testimonials.author_id = transactions.starter_id") }

  # Formats grade so that it can be displayed in the UI
  def displayed_grade
    (grade * 4 + 1).to_i
  end

  # 星 1〜5 を grade(0..1) に換算する（Issue #106 Phase 1）。
  # `displayed_grade`（grade*4+1）の逆変換。範囲外・非数値は nil を返し、
  # grade の inclusion 検証で弾く。
  #
  # @param stars [String, Integer, nil] UI から受け取った星の数
  # @return [Float, nil] 1→0.0, 2→0.25, 3→0.5, 4→0.75, 5→1.0
  def self.grade_from_stars(stars)
    star = Integer(stars, exception: false)
    return nil if star.nil? || !STARS.cover?(star)

    (star - 1) / 4.0
  end

  def positive?
    grade >= 0.5
  end

  private

  # 出品（ペルソナ）単位の評価か。取引レビューは false。
  def listing_review?
    listing_id.present?
  end

  # 影響を受けた出品の集計を再計算する。
  #
  # 例外は飲み込んでログに残す。after_commit の時点でレビューは確定しており、
  # ここで投げ直しても巻き戻せない一方、投稿者には 500 が返り「投稿できたか
  # 分からない」状態を作ってしまう。集計は表示用のキャッシュなので、
  # `lamprey:normalize_listing_ratings` で後から修復できる。
  def refresh_listing_rating
    affected_listing_ids.each do |id|
      ListingRatingService.recalculate!(id)
    end
  rescue StandardError => e
    Rails.logger.error(
      "[ListingRatingService] listing_ids=#{affected_listing_ids.inspect} " \
      "#{e.class}: #{e.message}"
    )
  end

  # 再計算すべき出品の ID。update で紐付け先が変わった場合は、移動元の集計も
  # 直さないと古い値が残るため両方を返す。取引レビューは空配列。
  def affected_listing_ids
    previous_listing_id = previous_changes["listing_id"]&.first
    [listing_id, previous_listing_id].compact.uniq
  end
end
