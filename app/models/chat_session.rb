# frozen_string_literal: true

# == Schema Information
#
# Table name: chat_sessions
#
#  id            :bigint           not null, primary key
#  person_id     :string(22)       not null
#  listing_id    :integer          not null
#  status        :string           default("active"), not null
#  billing_model :string
#  started_at    :datetime
#  ended_at      :datetime
#  total_tokens  :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  title         :string(100)
#  channel       :string           default("web"), not null
#
# Indexes
#
#  index_chat_sessions_on_listing_id_and_person_id  (listing_id,person_id)
#  index_chat_sessions_on_person_id_and_status      (person_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (listing_id => listings.id)
#

class ChatSession < ApplicationRecord
  STATUSES = %w[active closed].freeze

  # 実行経路（Issue #148 第 1 段）。
  #   web — ブラウザのチャット UI（DB の既定値）
  #   mcp — 外部クライアント（MCP ツール / #144 の実行 API）
  # ジョブがこの値を `usage_records.channel` に写す。値の制約はまだ無い
  # （#146 / #147 で経路列・一覧を出す際に絞るかどうかを決める）。
  CHANNEL_MCP = "mcp"

  belongs_to :listing
  # people.id is varchar(22) without UNIQUE, so DB-level FK is skipped.
  # Referential integrity is enforced at the application level.
  belongs_to :person
  has_many :chat_messages, dependent: :destroy
  has_many :chat_attachments, dependent: :destroy

  validates :person_id, presence: true
  validates :listing_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
  scope :for_person, ->(person) { where(person_id: person.id) }
  # AI 応答（assistant メッセージ）が 1 件以上あるセッション（Issue #106 Phase 1）。
  # ペルソナ評価は「実際に AI の回答を受け取ったこと」を投稿根拠にするため、
  # user メッセージのみのセッション（未回答・失敗）は対象外とする。
  scope :with_assistant_message, -> {
    joins(:chat_messages).where(chat_messages: { role: "assistant" }).distinct
  }

  # Builds the system prompt from the associated Listing's persona fields.
  #
  # The seller's skill markdown is what the buyer is paying for, and it is
  # never shown on the public listing. It is therefore sent verbatim as the
  # system prompt. The listing's description is the storefront copy, not the
  # persona definition, so it stays out of the AI context.
  #
  # @return [String, nil] the system prompt, or nil if the seller wrote no skill
  def system_prompt
    listing_obj = listing
    return nil unless listing_obj

    return nil if listing_obj.skill_markdown.blank?

    listing_obj.skill_markdown.strip
  end

  # Mark this session as closed and record the end time.
  def close!
    update!(status: "closed", ended_at: Time.current)
  end

  # 課金モデルの表示用の値（サーバー側で決める。クライアントの指定は使わない）。
  # 実際の請求は `BillingService` が subscription から決めるため、この値は
  # セッション一覧の表示のみに使う。
  #
  # セッションを作る経路が複数ある（chat_sessions#create と #144 の実行 API）
  # ため、判定はここ 1 箇所に置く。
  #
  # @param person [Person]
  # @param listing [Listing]
  # @return [String] subscription_with_overage / token_based
  def self.billing_model_for(person:, listing:)
    subscription = UserPlanSubscription.find_by(
      person: person,
      listing: listing,
      status: "active"
    )
    return "token_based" if subscription.nil?

    subscription.billing_model.presence || "subscription_with_overage"
  end
end
