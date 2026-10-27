# frozen_string_literal: true

require 'rails_helper'

# 販売数の加算（Issue #98）。
#
# アシスタント回答の確定は課金成功と同一トランザクションのため、
# commit 後のフックで total_sold を数える。BillingService 側は親作業中のため触らない。
RSpec.describe ChatMessage, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: person) }
  let(:chat_session) { FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id) }

  it "アシスタント回答の確定で total_sold が 1 増える" do
    expect {
      FactoryBot.create(:chat_message, chat_session: chat_session, role: "assistant", content: "回答")
    }.to change { listing.reload.total_sold }.by(1)
  end

  it "user メッセージでは total_sold は増えない" do
    expect {
      FactoryBot.create(:chat_message, chat_session: chat_session, role: "user", content: "質問")
    }.not_to(change { listing.reload.total_sold })
  end

  it "トランザクションがロールバックしたら total_sold は増えない" do
    expect {
      ActiveRecord::Base.transaction do
        FactoryBot.create(:chat_message, chat_session: chat_session, role: "assistant", content: "回答")
        raise ActiveRecord::Rollback
      end
    }.not_to(change { listing.reload.total_sold })
  end
end
