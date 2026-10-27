# frozen_string_literal: true

require 'rails_helper'

# Issue #82 E2E: 有料出品でのチャット→課金→残高更新の一連フロー。
# AIアダプターのみスタブし、BillingService・Wallet は本物を使う。
RSpec.describe "チャット課金のE2E（Issue #82）", type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:seller) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: seller) }
  let(:chat_session) do
    FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
  end
  let(:adapter) { instance_double(Ai::OpenAiAdapter) }
  let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 10_000) }

  before do
    allow(Ai::ProviderFactory).to receive(:for).with(listing).and_return(adapter)
    allow(adapter).to receive(:ai_model).and_return(
      FactoryBot.create(:ai_model, ai_provider: FactoryBot.create(:ai_provider))
    )
    allow(adapter).to receive(:stream).and_yield({ content: "こんにちは。" })
    allow(adapter).to receive(:last_usage).and_return(
      OpenStruct.new(input_tokens: 100, output_tokens: 50)
    )
    allow(adapter).to receive(:last_finish_reason).and_return(nil)
    allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
    allow(ActionCable.server).to receive(:broadcast)
  end

  it "課金で残高が減り、stream_done に課金後残高が載る" do
    broadcasts = []
    allow(ActionCable.server).to receive(:broadcast) do |channel, payload|
      broadcasts << [channel, payload]
    end

    before_balance = wallet.reload.balance_cents
    PersonaExecutorJob.new(chat_session.id, "msg-1", "こんにちは").perform
    after_balance = wallet.reload.balance_cents

    expect(after_balance).to be < before_balance
    done = broadcasts.find { |(_ch, p)| p[:type] == "stream_done" }
    expect(done).not_to be_nil
    expect(done[1][:current_balance]).to eq(wallet.reload.balance_cents)
    expect(UsageRecord.count).to be >= 1
  end
end
