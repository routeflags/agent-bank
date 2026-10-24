# frozen_string_literal: true

require 'rails_helper'

# 購入権利（UserPlanSubscription）が付与される経路の回帰テスト。
#
#   * confirmed 遷移（実決済の完了）→ 付与される
#   * free 遷移（決済なしで成立した取引 = コンタクト等）→ 付与されない
#
# free 遷移で付与してしまうと「有料ペルソナにコンタクトしただけで購入権利と
# 初回トークンが得られる」購入偽装になるため、明示的に固定する。
RSpec.describe "Persona purchase entitlement", type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:buyer) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: author) }

  # 取引を 1 件作り、Statesman が読む transitions 履歴を 1 件作る。
  def build_transaction(state, listing:, payment_gateway: "stripe")
    conversation = FactoryBot.create(:conversation, community: community)
    FactoryBot.create(:participation, conversation: conversation, person: author, is_starter: true)
    FactoryBot.create(:participation, conversation: conversation, person: buyer, is_starter: false)

    tx = FactoryBot.create(:transaction,
                           community: community,
                           listing: listing,
                           starter: buyer,
                           listing_author: author,
                           conversation: conversation,
                           current_state: state,
                           payment_gateway: payment_gateway)
    FactoryBot.create(:transaction_transition, to_state: state.to_s,
                                               transaction_id: tx.id, most_recent: true)
    tx
  end

  describe "confirmed 遷移（実決済の完了）" do
    it "active な購入権利と初回トークンを付与する" do
      tx = build_transaction(:paid, listing: listing)

      expect {
        TransactionService::StateMachine.transition_to(tx.id, "confirmed")
      }.to change(UserPlanSubscription, :count).by(1)

      expect(tx.reload.current_state).to eq("confirmed")
      expect(UserPlanSubscription.last.status).to eq("active")
      expect(buyer.reload.wallet.balance_cents).to be > 0
    end
  end

  describe "free 遷移（決済なしで成立した取引）" do
    it "有料ペルソナへのコンタクトでは購入権利を付与しない" do
      tx = build_transaction("not_started", listing: listing, payment_gateway: "none")

      expect {
        TransactionService::StateMachine.transition_to(tx.id, "free")
      }.not_to change(UserPlanSubscription, :count)

      expect(tx.reload.current_state).to eq("free")
    end

    it "価格0（旧来データ）の出品へのコンタクトでも購入権利を付与しない" do
      # Issue #52: 価格 0 の出品は新規作成できない。旧来データ相当としてバリデーションを迂回する。
      free_listing = FactoryBot.build(:listing, community_id: community.id,
                                                author: author, price: Money.new(0, "USD"))
      free_listing.save!(validate: false)
      tx = build_transaction("not_started", listing: free_listing, payment_gateway: "none")

      expect {
        TransactionService::StateMachine.transition_to(tx.id, "free")
      }.not_to change(UserPlanSubscription, :count)
    end
  end
end
