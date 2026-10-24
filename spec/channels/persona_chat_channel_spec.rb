# frozen_string_literal: true

require 'rails_helper'

# PersonaChatChannel の受信経路の回帰 spec（Issue #32）。
#
# 購入後にチャット送信が動作しない問題（receive 未実行・Job 未投入）の
# 再発を防ぐ。クライアント側の送信取りこぼし対策（ChatPanelApp.js の
# 待機列・明示的 sessionId）と対になるサーバー側の担保である。
RSpec.describe PersonaChatChannel, type: :channel do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: person) }
  let(:chat_session) do
    FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
  end

  before do
    stub_connection(current_user: person)
  end

  describe "購読" do
    it "持ち主のセッションを購読できる" do
      subscribe(chat_session_id: chat_session.id)
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("persona_chat_#{chat_session.id}")
    end

    it "存在しないセッションは reject する" do
      subscribe(chat_session_id: -1)
      expect(subscription).to be_rejected
    end

    it "他人のセッションは reject する" do
      other_session = FactoryBot.create(:chat_session, person_id: other_person.id, listing_id: listing.id)
      subscribe(chat_session_id: other_session.id)
      expect(subscription).to be_rejected
    end
  end

  describe "#receive" do
    before do
      subscribe(chat_session_id: chat_session.id)
    end

    it "ユーザーメッセージを保存する" do
      allow(Delayed::Job).to receive(:enqueue)
      expect {
        perform :receive, { "chat_session_id" => chat_session.id, "content" => "こんにちは" }
      }.to change { chat_session.chat_messages.count }.by(1)
      message = chat_session.chat_messages.order(:seq).last
      expect(message.content).to eq("こんにちは")
      expect(message.role).to eq("user")
    end

    it "PersonaExecutorJob を投入する" do
      expect(Delayed::Job).to receive(:enqueue).with(kind_of(PersonaExecutorJob), hash_including(priority: 0))
      perform :receive, { "chat_session_id" => chat_session.id, "content" => "こんにちは" }
    end

    it "実行設定を metadata に保存する（ホワイトリストのみ）" do
      allow(Delayed::Job).to receive(:enqueue)
      perform :receive, {
        "chat_session_id" => chat_session.id,
        "content" => "設定付き送信",
        "settings" => { "token_limit" => 8000, "output_length" => "long", "tone" => "casual", "evil" => "x" }
      }
      message = chat_session.chat_messages.order(:seq).last
      settings = message.metadata["settings"]
      expect(settings["token_limit"]).to eq(8000)
      expect(settings["output_length"]).to eq("long")
      expect(settings["tone"]).to eq("casual")
      expect(settings).not_to have_key("evil")
    end

    it "存在しないセッションでは保存も投入もしない" do
      expect(Delayed::Job).not_to receive(:enqueue)
      expect {
        perform :receive, { "chat_session_id" => -1, "content" => "こんにちは" }
      }.not_to(change { ChatMessage.count })
    end

    it "他人のセッションでは保存も投入もしない" do
      other_session = FactoryBot.create(:chat_session, person_id: other_person.id, listing_id: listing.id)
      expect(Delayed::Job).not_to receive(:enqueue)
      expect {
        perform :receive, { "chat_session_id" => other_session.id, "content" => "なりすまし" }
      }.not_to(change { ChatMessage.count })
    end
  end
end
