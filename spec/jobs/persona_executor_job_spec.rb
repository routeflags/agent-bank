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
        allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
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
      before { allow_any_instance_of(Person).to receive(:wallet).and_return(nil) }

      it "error_type を含まない stream_error を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error: "ウォレットが見つかりません。先にウォレットを追加してください。"
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
        allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
        allow(Ai::ProviderFactory).to receive(:for)
          .and_raise(Ai::ProviderFactory::ProviderNotConfiguredError, "No provider")
      end

      it "error_type を含まない stream_error を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error: "このペルソナのAIプロバイダーが設定されていません。"
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

  # ── AI プロバイダーのエラー分類 ──────────────────────

  describe "AI プロバイダーのエラー" do
    let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 1000) }

    before do
      allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
    end

    context "利用枠の枯渇（429 / credit_balance_exhausted）" do
      before do
        allow(adapter).to receive(:stream).and_raise(
          Ai::OpenAiAdapter::ApiError.new(
            "OpenAI streaming error: HTTP 429: Too Many Requests",
            status: 429,
            code: "credit_balance_exhausted"
          )
        )
      end

      it "運営への連絡を促すメッセージを provider_billing_error として broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error_type: "provider_billing_error",
            error: "AIの利用枠が不足しているため応答できません。運営にお問い合わせください。"
          )
        )

        PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello").perform
      end

      it "エラーをシステムメッセージとして履歴に残す" do
        allow(ActionCable.server).to receive(:broadcast)

        expect {
          PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello").perform
        }.to change { chat_session.chat_messages.where(role: "system").count }.by(1)
      end
    end

    context "認証エラー（401）" do
      before do
        allow(adapter).to receive(:stream).and_raise(
          Ai::OpenAiAdapter::ApiError.new("OpenAI API error (401)", status: 401)
        )
      end

      it "接続設定の問題として provider_auth_error を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error_type: "provider_auth_error",
            error: "AIの接続設定に問題があるため応答できません。運営にお問い合わせください。"
          )
        )

        PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello").perform
      end
    end

    context "分類できないエラー" do
      before do
        allow(adapter).to receive(:stream).and_raise(
          Ai::OpenAiAdapter::ApiError.new("OpenAI streaming error: HTTP 500")
        )
      end

      it "汎用メッセージを error_type なしで broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(
            type: "stream_error",
            error: "リクエストの処理中にエラーが発生しました。もう一度お試しください。"
          )
        ).and_wrap_original do |_method, *args|
          expect(args.last).not_to have_key(:error_type)
        end

        PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello").perform
      end
    end
  end

  # ── is_result auto-detection (Result panel) ──────────────────────

  describe "成果物判定 (is_result)" do
    let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 1000) }

    before do
      allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
      allow(adapter).to receive(:last_usage).and_return(
        OpenStruct.new(input_tokens: 10, output_tokens: 5)
      )
      allow(adapter).to receive(:last_finish_reason).and_return(nil)
      billing_service = instance_double(BillingService)
      allow(BillingService).to receive(:new).and_return(billing_service)
      allow(billing_service).to receive(:process!).and_return(
        { base_cost_cents: 1, platform_commission_cents: 0, seller_payout_cents: 1, total_charge_cents: 1 }
      )
    end

    context "応答にコードブロックが含まれる場合" do
      before do
        allow(adapter).to receive(:stream).and_yield({ content: "```ruby\nputs 'hi'\n```" })
        allow(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(type: "stream_chunk")
        )
      end

      it "stream_done に is_result: true を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(type: "stream_done", is_result: true)
        ).and_call_original

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "コードを書いて")
        job.perform
      end

      it "メッセージの metadata に is_result を保存する" do
        allow(ActionCable.server).to receive(:broadcast)

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "コードを書いて")
        job.perform

        message = chat_session.chat_messages.order(:seq).last
        expect(message.metadata["is_result"]).to be true
      end
    end

    context "通常の短い応答の場合" do
      before do
        allow(adapter).to receive(:stream).and_yield({ content: "はい、了解しました。" })
        allow(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(type: "stream_chunk")
        )
      end

      it "stream_done に is_result: false を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(type: "stream_done", is_result: false)
        ).and_call_original

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "お願いします")
        job.perform
      end

      it "metadata に is_result を保存しない" do
        allow(ActionCable.server).to receive(:broadcast)

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "お願いします")
        job.perform

        message = chat_session.chat_messages.order(:seq).last
        expect(message.metadata).to be_nil
      end
    end
  end

  # ── Wallet::InsufficientBalanceError rescue ───────────────────────

  describe "Wallet::InsufficientBalanceError の rescue 処理" do
    before do
      wallet = FactoryBot.create(:wallet, person: person, community: community, balance_cents: 100)
      allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)

      # Mock adapter to succeed streaming but fail at billing
      allow(adapter).to receive(:stream).and_yield({ content: "Hi" })
      allow(adapter).to receive(:last_usage).and_return(
        OpenStruct.new(input_tokens: 10, output_tokens: 5)
      )
      allow(adapter).to receive(:last_finish_reason).and_return(nil)

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

  # ── トークン上限の引き渡し（Issue #105） ──────────────────────

  describe "トークン上限の引き渡し" do
    let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 1000) }

    before do
      allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
      allow(adapter).to receive(:stream).and_yield({ content: "Hi" })
      allow(adapter).to receive(:last_usage).and_return(
        OpenStruct.new(input_tokens: 10, output_tokens: 5)
      )
      allow(adapter).to receive(:last_finish_reason).and_return("stop")
      billing_service = instance_double(BillingService)
      allow(BillingService).to receive(:new).and_return(billing_service)
      allow(billing_service).to receive(:process!).and_return(
        { base_cost_cents: 1, platform_commission_cents: 0, seller_payout_cents: 1, total_charge_cents: 1 }
      )
      allow(ActionCable.server).to receive(:broadcast)
    end

    def perform_with_token_limit(token_limit)
      user_message = chat_session.chat_messages.create!(
        content: "Hello",
        sender_type: "Person",
        sender_id: person.id,
        role: "user",
        seq: 1,
        metadata: { "settings" => { "token_limit" => token_limit } }
      )
      PersonaExecutorJob.new(chat_session.id, user_message.id, "Hello").perform
    end

    it "nil（上限なし）は残高候補とモデル上限の小さい方を渡す（Issue #104）" do
      # #105 の素通しは #104 の安全弁で上書きされる。「上限なし」は無限ではなく
      # min(残高候補, モデル上限) に確定する。ここでは残高が潤沢なためモデル上限になる。
      perform_with_token_limit(nil)
      expect(adapter).to have_received(:stream).with(
        anything, hash_including(max_tokens: adapter.ai_model.max_tokens)
      )
    end

    it "20_000 はモデル上限でクリップして渡す（Issue #102(1) 解決順 3）" do
      # #105 の素通し契約は #102(1) で上書きされる。係数適用後（ここでは
      # output_length 未指定 = standard ×1.0）の値がモデル上限を超える場合は
      # モデル上限が勝つ。残高が潤沢なため残高クリップは働かない。
      perform_with_token_limit(20_000)
      expect(adapter).to have_received(:stream).with(
        anything, hash_including(max_tokens: adapter.ai_model.max_tokens)
      )
    end

    it "4_000 は従来どおり渡す" do
      perform_with_token_limit(4_000)
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 4000))
    end
  end

  # ── 打ち切り記録 (finish_reason / Issue #63) ──────────────────────

  describe "トークン上限による打ち切りの記録" do
    let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 1000) }

    before do
      allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
      allow(adapter).to receive(:last_usage).and_return(
        OpenStruct.new(input_tokens: 10, output_tokens: 5)
      )
      billing_service = instance_double(BillingService)
      allow(BillingService).to receive(:new).and_return(billing_service)
      allow(billing_service).to receive(:process!).and_return(
        { base_cost_cents: 1, platform_commission_cents: 0, seller_payout_cents: 1, total_charge_cents: 1 }
      )
      allow(ActionCable.server).to receive(:broadcast)
    end

    context "上限打ち切り（length）の場合" do
      before do
        allow(adapter).to receive(:stream)
          .and_yield({ content: "長い回答の前半", finish_reason: "length" })
        allow(adapter).to receive(:last_finish_reason).and_return("length")
      end

      it "metadata に truncated と finish_reason を保存する" do
        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform

        message = chat_session.chat_messages.order(:seq).last
        expect(message.role).to eq("assistant")
        expect(message.metadata["truncated"]).to be true
        expect(message.metadata["finish_reason"]).to eq("length")
      end

      it "stream_done に truncated: true と finish_reason を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(type: "stream_done", truncated: true, finish_reason: "length")
        ).and_call_original

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform
      end
    end

    context "正常完結（stop）の場合" do
      before do
        allow(adapter).to receive(:stream)
          .and_yield({ content: "はい、了解しました。" })
        allow(adapter).to receive(:last_finish_reason).and_return("stop")
      end

      it "metadata に truncated を保存しない（従来どおり）" do
        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "お願いします")
        job.perform

        message = chat_session.chat_messages.order(:seq).last
        expect(message.metadata).to be_nil
      end

      it "stream_done に truncated: false を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(type: "stream_done", truncated: false, finish_reason: "stop")
        ).and_call_original

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "お願いします")
        job.perform
      end
    end

    context "Anthropic の max_tokens の場合" do
      before do
        allow(adapter).to receive(:stream)
          .and_yield({ content: "長い回答の前半", stop_reason: "max_tokens" })
        allow(adapter).to receive(:last_finish_reason).and_return("max_tokens")
      end

      it "metadata に truncated と finish_reason を保存する" do
        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform

        message = chat_session.chat_messages.order(:seq).last
        expect(message.metadata["truncated"]).to be true
        expect(message.metadata["finish_reason"]).to eq("max_tokens")
      end

      it "stream_done に truncated: true を broadcast する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "persona_chat_#{chat_session.id}",
          hash_including(type: "stream_done", truncated: true, finish_reason: "max_tokens")
        ).and_call_original

        job = PersonaExecutorJob.new(chat_session.id, "msg-1", "Hello")
        job.perform
      end
    end
  end

  # ── 残高による出力上限のクリップ（Issue #104） ──────────────────
  # 当 worktree には #104 が未存在だったため、同等ロジックの移植とともに
  # 受入表を spec で固定する（main の 2278e1fd8 と同内容）。

  describe "残高による出力上限のクリップ" do
    let(:listing) do
      FactoryBot.create(:listing, community_id: community.id, author: person,
                                  price: Money.new(1_000, "JPY"))
    end
    let(:ai_model) do
      FactoryBot.create(:ai_model, ai_provider: FactoryBot.create(:ai_provider),
                                   max_tokens: 16_384)
    end
    let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 10) }

    before do
      allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
      allow(adapter).to receive(:ai_model).and_return(ai_model)
      allow(adapter).to receive(:stream).and_yield({ content: "Hi" })
      allow(adapter).to receive(:last_usage).and_return(
        OpenStruct.new(input_tokens: 10, output_tokens: 5)
      )
      allow(adapter).to receive(:last_finish_reason).and_return("stop")
      billing_service = instance_double(BillingService)
      allow(BillingService).to receive(:new).and_return(billing_service)
      allow(billing_service).to receive(:process!).and_return(
        { base_cost_cents: 1, platform_commission_cents: 0, seller_payout_cents: 1, total_charge_cents: 1 }
      )
      allow(ActionCable.server).to receive(:broadcast)
    end

    def perform_with_content(content, token_limit)
      user_message = chat_session.chat_messages.create!(
        content: content,
        sender_type: "Person",
        sender_id: person.id,
        role: "user",
        seq: 1,
        metadata: { "settings" => { "token_limit" => token_limit } }
      )
      PersonaExecutorJob.new(chat_session.id, user_message.id, content).perform
    end

    it "残高10円・上限なし・入力223文字なら 9,777 以下にクリップする" do
      perform_with_content("あ" * 223, nil)
      # 予算 10,000 - 入力見積り (223 + 4) = 9,773（モデル上限 16,384 より小さい）
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 9_773))
    end

    it "残高1,000円・上限なしなら残高クリップは働かずモデル上限になる" do
      wallet.update!(balance_cents: 1_000)
      perform_with_content("Hello", nil)
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 16_384))
    end

    it "ユーザー指定値は残高候補との小さい方になる" do
      perform_with_content("あ" * 223, 20_000)
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 9_773))
    end

    it "ユーザー指定値が候補より小さければ指定どおりになる" do
      perform_with_content("Hello", 4_000)
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 4_000))
    end

    it "入力だけで予算超過なら API を呼ばず insufficient_balance で拒否する" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "persona_chat_#{chat_session.id}",
        hash_including(type: "stream_error", error_type: "insufficient_balance")
      )
      perform_with_content("あ" * 12_000, nil)
      expect(adapter).not_to have_received(:stream)
    end

    it "残高5円・履歴が長い場合は拒否される（開始時ゲート）" do
      wallet.update!(balance_cents: 5)
      expect(ActionCable.server).to receive(:broadcast).with(
        "persona_chat_#{chat_session.id}",
        hash_including(type: "stream_error", error_type: "insufficient_balance")
      )
      perform_with_content("あ" * 6_000, nil)
      expect(adapter).not_to have_received(:stream)
    end

    it "単価未設定の出品はクリップせず素通しする" do
      listing.update_column(:price_cents, nil)
      perform_with_content("Hello", 4_000)
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 4_000))
      perform_with_content("Hello", nil)
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: nil))
    end
  end

  # ── output_length の max_tokens 連動（Issue #102(1)） ──────────
  #
  # 解決順: 1. token_limit（nil = 上限なし）→ 2. 係数を掛ける（short ×0.5 /
  # standard ×1.0 / long ×2.0、端数切捨て）→ 3. モデル上限でクリップ →
  # 4. 残高クリップと min。受入基準の 6 行を固定する。

  describe "output_length の max_tokens 連動" do
    let(:listing) do
      FactoryBot.create(:listing, community_id: community.id, author: person,
                                  price: Money.new(1_000, "JPY"))
    end
    let(:ai_model) do
      FactoryBot.create(:ai_model, ai_provider: FactoryBot.create(:ai_provider),
                                   max_tokens: 16_384)
    end
    let!(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 100_000) }

    before do
      allow_any_instance_of(Person).to receive(:wallet).and_return(wallet)
      allow(adapter).to receive(:ai_model).and_return(ai_model)
      allow(adapter).to receive(:stream).and_yield({ content: "Hi" })
      allow(adapter).to receive(:last_usage).and_return(
        OpenStruct.new(input_tokens: 10, output_tokens: 5)
      )
      allow(adapter).to receive(:last_finish_reason).and_return("stop")
      billing_service = instance_double(BillingService)
      allow(BillingService).to receive(:new).and_return(billing_service)
      allow(billing_service).to receive(:process!).and_return(
        { base_cost_cents: 1, platform_commission_cents: 0, seller_payout_cents: 1, total_charge_cents: 1 }
      )
      allow(ActionCable.server).to receive(:broadcast)
    end

    def perform_with_output_length(content, token_limit, output_length)
      user_message = chat_session.chat_messages.create!(
        content: content,
        sender_type: "Person",
        sender_id: person.id,
        role: "user",
        seq: 1,
        metadata: { "settings" => { "token_limit" => token_limit, "output_length" => output_length } }
      )
      PersonaExecutorJob.new(chat_session.id, user_message.id, content).perform
    end

    it "token_limit=8_000 + long → 16_000（モデル上限 16,384 に収まる）" do
      perform_with_output_length("Hello", 8_000, "long")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 16_000))
    end

    it "token_limit=8_000 + short → 4_000" do
      perform_with_output_length("Hello", 8_000, "short")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 4_000))
    end

    it "token_limit=8_000 + standard → 8_000（従来どおり）" do
      perform_with_output_length("Hello", 8_000, "standard")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 8_000))
    end

    it "token_limit=nil（上限なし）は係数を適用せずモデル上限に従う" do
      perform_with_output_length("Hello", nil, "long")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 16_384))
    end

    it "残高クリップが係数適用後より小さい場合は残高側が勝つ" do
      wallet.update!(balance_cents: 10)
      # 予算 10,000 - 入力見積り ((223 + 24) + 4×2 = 255) = 9,745 < 16_000（8_000 × long）。
      # long の指示文（24字）が system として送られる分も入力見積りに含まれる。
      perform_with_output_length("あ" * 223, 8_000, "long")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 9_745))
    end

    it "モデル上限が係数適用後より小さい場合はモデル上限が勝つ" do
      ai_model.update!(max_tokens: 8_192)
      # 8_000 × long = 16_000 > 8_192。残高は潤沢なため残高クリップは働かない。
      perform_with_output_length("Hello", 8_000, "long")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 8_192))
    end

    it "未知の output_length は standard 扱い（係数 1.0）" do
      perform_with_output_length("Hello", 8_000, "evil")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 8_000))
    end

    it "端数は切り捨てる（トークンは整数）" do
      perform_with_output_length("Hello", 3_333, "short")
      expect(adapter).to have_received(:stream).with(anything, hash_including(max_tokens: 1_666))
    end
  end
end
