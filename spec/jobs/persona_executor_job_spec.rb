# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonaExecutorJob, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: person) }
  let(:chat_session) do
    FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
  end

  let(:adapter) { instance_double(Ai::OpenAiAdapter) }

  before do
    # Stub the provider factory to return our mock adapter
    allow(Ai::ProviderFactory).to receive(:for).with(listing).and_return(adapter)
    allow(adapter).to receive(:ai_model).and_return(
      FactoryBot.create(:ai_model, ai_provider: FactoryBot.create(:ai_provider))
    )
  end

  # ── broadcast_error with error_type ──────────────────────────────

  describe "broadcast_error に error_type を含める" do
    context "残高不足の場合" do
      let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 0) }

      before do
        # chat_session.person は DB からロードされるため、Wallet.find_by でスタブする
        allow(Wallet).to receive(:find_by).and_return(wallet)
      end

      it "error_type: insufficient_balance を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error_type: "insufficient_balance",
            current_balance: 0
          )
        )

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform
      end

      it "current_balance に現在の残高を含める" do
        wallet.update!(balance_cents: 5)

        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error_type: "insufficient_balance",
            current_balance: 5
          )
        )

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform
      end
    end

    context "Wallet が存在しない場合" do
      before { allow(Wallet).to receive(:find_by).and_return(nil) }

      it "error_type を含まない stream_error を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error: "Wallet not found. Please add funds to continue."
          )
        ).and_wrap_original do |_method, *args|
          # Verify error_type is NOT present
          payload = args.last
          expect(payload).not_to have_key(:error_type)
        end

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform
      end
    end

    context "AI プロバイダーが未設定の場合" do
      let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 1000) }

      before do
        allow(Wallet).to receive(:find_by).and_return(wallet)
        allow(Ai::ProviderFactory).to receive(:for)
          .and_raise(Ai::ProviderFactory::ProviderNotConfiguredError, "No provider")
      end

      it "error_type を含まない stream_error を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error: "AI provider is not configured for this persona."
          )
        ).and_wrap_original do |_method, *args|
          payload = args.last
          expect(payload).not_to have_key(:error_type)
        end

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform
      end
    end
  end

  # ── Wallet::InsufficientBalanceError rescue ───────────────────────

  describe "Wallet::InsufficientBalanceError の rescue 処理" do
    before do
      wallet = FactoryBot.create(:wallet, person: person, community: community, balance_cents: 100)
      allow(Wallet).to receive(:find_by).and_return(wallet)

      # Mock adapter to succeed streaming but fail at billing
      allow(adapter).to receive(:stream).and_yield({ content: "Hi" })
      allow(adapter).to receive(:last_usage).and_return(
        OpenStruct.new(input_tokens: 10, output_tokens: 5)
      )

      # Stub BillingService to raise insufficient balance during deduction
      billing_service = instance_double(BillingService)
      allow(BillingService).to receive(:new).and_return(billing_service)
      allow(billing_service).to receive(:process!).and_raise(
        Wallet::InsufficientBalanceError, "Insufficient balance: 100 < 500"
      )
    end

    it "error_type: insufficient_balance で broadcast する" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "persona_chat_#{chat_session.id}",
        hash_including(
          type: "stream_chunk"
        )
      ).at_least(:once)

      expect(ActionCable.server).to receive(:broadcast).with(
        "persona_chat_#{chat_session.id}",
        hash_including(
          type: "stream_error",
          error_type: "insufficient_balance"
        )
      )

      job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
      job.perform
    end
  end
end
