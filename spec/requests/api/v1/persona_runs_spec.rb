# frozen_string_literal: true

require 'rails_helper'

# ペルソナ実行 API（Issue #144）と、その利用記録の経路（#148 第 1 段）。
#
# AI アダプターだけをスタブし、BillingService / Wallet / PersonaExecutorJob は
# 本物を通す（1 リクエスト = 1 ジョブ = UsageRecord 1 行を実際に確かめる）。
RSpec.describe "Api::V1::PersonaRuns", type: :request do
  # 単価 1,000 円 / 100 万トークン。100+50 トークンで 0.15 円。
  let(:unit_price_cents) { 1_000 }
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }

  # スキル本文はサーバー側（system プロンプト）でだけ使い、応答に全文を出さない。
  let(:skill_markdown) { "# スキル\n" + ("あ" * 200) + "SKILL-TAIL-MUST-NOT-LEAK" }
  let(:listing) do
    FactoryBot.create(
      :listing,
      community_id: community.id,
      author: other_person,
      title: "相談役",
      price: Money.new(unit_price_cents, "JPY"),
      skill_markdown: skill_markdown
    )
  end

  let(:wallet) { FactoryBot.create(:wallet, person: person, community: community, balance_cents: 10_000) }
  let(:adapter) { instance_double(Ai::OpenAiAdapter) }
  let(:ai_model) do
    FactoryBot.create(
      :ai_model,
      ai_provider: FactoryBot.create(:ai_provider),
      cost_per_1k_input: 1.0,
      cost_per_1k_output: 2.0
    )
  end

  # 実行 scope を持つトークン（read を包含する）。
  let(:scopes) { %w[read run] }
  let!(:issued_token) { APIToken.issue!(person: person, name: "MCP", scopes: scopes) }
  let(:token_record) { issued_token.first }
  let(:auth_headers) { { "Authorization" => "Bearer #{issued_token.last}" } }
  let(:lock_name) { "api_run_token:#{token_record.id}" }

  let(:message) { "こんにちは。1 行で自己紹介してください。" }

  before do
    wallet
    stub_provider
    allow(ActionCable.server).to receive(:broadcast)
  end

  # AI アダプターのスタブ。本物の API は叩かない。
  def stub_provider(content: "はじめまして。相談役です。", input_tokens: 100, output_tokens: 50)
    allow(Ai::ProviderFactory).to receive(:for).with(listing).and_return(adapter)
    allow(adapter).to receive(:ai_model).and_return(ai_model)
    allow(adapter).to receive(:stream).and_yield({ content: content })
    allow(adapter).to receive(:last_usage).and_return(
      OpenStruct.new(input_tokens: input_tokens, output_tokens: output_tokens)
    )
    allow(adapter).to receive(:last_finish_reason).and_return(nil)
  end

  def json
    JSON.parse(response.body)
  end

  def post_run(headers: auth_headers, **payload)
    post "/api/v1/personas/#{listing.id}/run", params: payload, headers: headers, as: :json
  end

  # =====================================================================
  # 正常系
  # =====================================================================
  describe "POST /api/v1/personas/:id/run" do
    it "アシスタントの応答と利用量を返し、経路 mcp で 1 行だけ記録する" do
      expect { post_run(message: message) }.to change { UsageRecord.count }.by(1)

      expect(response).to have_http_status(200)
      expect(json["content"]).to eq("はじめまして。相談役です。")
      expect(json["usage"]["total_tokens"]).to eq(150)
      # usage_records.cost_cents は AI モデルの原価（$/1k からの換算）。
      # 100/1000*1.0 + 50/1000*2.0 = 0.2 円 → 20 銭。
      expect(json["usage"]["cost_cents"]).to eq(20.0)

      usage_record = UsageRecord.last
      expect(json["usage"]["cost_cents"]).to eq(usage_record.cost_cents.to_f)
      expect(json["usage"]["total_tokens"]).to eq(usage_record.total_tokens)

      # Issue #148: 実行経路はセッションと利用記録の両方に残る。
      expect(usage_record.channel).to eq("mcp")
      expect(ChatSession.find(json["session_id"]).channel).to eq("mcp")

      # 課金は請求額（150 トークン × 単価 1,000 円）だけ引かれる。
      expect(json["balance_cents"]).to be_within(0.0001).of(9_999.85)
      expect(wallet.reload.balance_cents.to_f).to be_within(0.0001).of(9_999.85)

      session = ChatSession.find(json["session_id"])
      expect(session.person_id).to eq(person.id)
      expect(session.chat_messages.order(:seq).map(&:role)).to eq(%w[user assistant])
    end

    it "スキル本文はサーバー側だけで使い、レスポンスには出さない" do
      post_run(message: message)

      expect(response).to have_http_status(200)
      expect(response.body).not_to include("SKILL-TAIL-MUST-NOT-LEAK")
    end

    it "レビュー集計（avg_rating / reviews_count）には影響しない" do
      expect { post_run(message: message) }.not_to(change { listing.reload.avg_rating })
      expect(listing.reviews_count).to eq(0)
    end

    it "session_id を渡すと同じセッションに追記する" do
      post_run(message: message)
      session_id = json["session_id"]

      expect { post_run(message: "もう 1 つ", session_id: session_id) }
        .to change { UsageRecord.count }.by(1)

      expect(response).to have_http_status(200)
      expect(json["session_id"]).to eq(session_id)
      expect(ChatSession.count).to eq(1)
      expect(ChatSession.find(session_id).chat_messages.order(:seq).map(&:role))
        .to eq(%w[user assistant user assistant])
    end

    # ===================================================================
    # 入力検証
    # ===================================================================
    it "message が空なら 422、記録は何も作らない" do
      expect { post_run(message: "") }.not_to(change { [ChatSession.count, UsageRecord.count] })

      expect(response).to have_http_status(422)
      expect(json["error"]).to eq("invalid_request")
    end

    it "message が無ければ 422" do
      post_run

      expect(response).to have_http_status(422)
      expect(json["error"]).to eq("invalid_request")
    end

    it "max_tokens が 0 なら 422" do
      post_run(message: message, max_tokens: 0)

      expect(response).to have_http_status(422)
      expect(json["error"]).to eq("invalid_request")
    end

    # ===================================================================
    # 参照できないペルソナ・セッション
    # ===================================================================
    it "存在しないペルソナは 404" do
      post "/api/v1/personas/0/run", params: { message: message }, headers: auth_headers, as: :json

      expect(response).to have_http_status(404)
      expect(json["error"]).to eq("persona_not_found")
    end

    it "他人のセッションは 404" do
      other_session = FactoryBot.create(
        :chat_session, person_id: other_person.id, listing_id: listing.id
      )

      expect { post_run(message: message, session_id: other_session.id) }
        .not_to(change { UsageRecord.count })

      expect(response).to have_http_status(404)
      expect(json["error"]).to eq("session_not_found")
    end

    it "別のペルソナのセッションは 404" do
      other_listing = FactoryBot.create(
        :listing, community_id: community.id, author: other_person, price: Money.new(1_000, "JPY")
      )
      session = FactoryBot.create(
        :chat_session, person_id: person.id, listing_id: other_listing.id
      )

      post_run(message: message, session_id: session.id)

      expect(response).to have_http_status(404)
      expect(json["error"]).to eq("session_not_found")
    end

    # ===================================================================
    # 残高ゲート（入口の 402）
    # ===================================================================
    context "残高が 0 のとき" do
      before { wallet.update!(balance_cents: 0) }

      it "402 insufficient_balance を返し、記録も課金もしない" do
        expect { post_run(message: message) }.not_to(change { UsageRecord.count })

        expect(response).to have_http_status(402)
        expect(json["error"]).to eq("insufficient_balance")
        expect(json["topup_url"]).to be_present
        expect(ChatSession.count).to eq(0)
        expect(wallet.reload.balance_cents.to_f).to eq(0.0)
      end

      it "topup_url はマイページ（チャージ導線がある画面）を指す" do
        post_run(message: message)

        expect(json["topup_url"]).to include(person.username)
      end
    end

    # ジョブ側でも残高が足りないと判断した場合（入口のゲートは通過する）。
    context "ジョブの残高クリップで不足するとき" do
      let(:unit_price_cents) { 1_000_000 } # 1 トークン = 1 円
      let(:message) { "あ" * 50 } # 入力見積りだけで予算を超える

      before { wallet.update!(balance_cents: 10) }

      it "アシスタント応答を作らず 402 insufficient_balance" do
        expect { post_run(message: message) }.not_to(change { UsageRecord.count })

        expect(response).to have_http_status(402)
        expect(json["error"]).to eq("insufficient_balance")
        expect(ChatSession.last.chat_messages.where(role: "assistant")).to be_empty
      end
    end

    # 生成はできたが、請求額（150 トークン × 1 円 = 150 円）が残高 100 円を
    # 超えた場合。ジョブはメッセージ作成と課金を同じトランザクションで行うので、
    # アシスタント応答も利用記録も残らない（＝二重課金もしない）。
    context "課金時に残高が足りないとき" do
      let(:unit_price_cents) { 1_000_000 }
      let(:message) { "あ" * 10 }
      let(:skill_markdown) { "短いスキル" }

      before { wallet.update!(balance_cents: 100) }

      it "アシスタント応答を残さず 402、利用記録は 0 行" do
        expect { post_run(message: message) }.not_to(change { UsageRecord.count })

        expect(response).to have_http_status(402)
        expect(json["error"]).to eq("insufficient_balance")
        expect(ChatSession.last.chat_messages.where(role: "assistant")).to be_empty
      end
    end

    # ===================================================================
    # max_tokens のクリップ（#104 の規則をここでは再現せず、ジョブに任せる）
    # ===================================================================
    context "max_tokens が残高に対して大きすぎるとき" do
      let(:unit_price_cents) { 1_000_000 } # 1 トークン = 1 円
      let(:message) { "あ" * 10 }
      let(:skill_markdown) { "短いスキル" }
      let(:requested_max_tokens) { 5_000 }

      before do
        wallet.update!(balance_cents: 100)
        # 入力見積り（23 トークン）より実際の消費を小さくして、課金（15 円）が
        # 残高 100 円に収まるようにする。
        stub_provider(input_tokens: 5, output_tokens: 10)
      end

      it "affordable_output_cap でクリップした値で実行する" do
        resolved = nil
        allow_any_instance_of(PersonaExecutorJob)
          .to receive(:resolve_max_tokens).and_wrap_original do |original, *args|
            resolved = original.call(*args)
          end

        used = nil
        allow(adapter).to receive(:stream) do |_messages, max_tokens:, &stream_block|
          used = max_tokens
          stream_block.call({ content: "短く答えます。" })
        end

        post_run(message: message, max_tokens: requested_max_tokens)

        expect(response).to have_http_status(200)
        expect(resolved).to eq(used)
        expect(used).to be < requested_max_tokens
        # 予算 = 残高 100 円 / 1 トークン 1 円。入力見積りを引いた値が上限。
        expect(used).to be <= 100
        expect(used).to be > 0
      end
    end

    # ===================================================================
    # AI プロバイダーが応答を作れなかった場合
    # ===================================================================
    context "プロバイダーが未設定のとき" do
      before do
        allow(Ai::ProviderFactory).to receive(:for)
          .and_raise(Ai::ProviderFactory::ProviderNotConfiguredError, "no provider")
      end

      it "502 run_failed を返し、課金しない" do
        expect { post_run(message: message) }.not_to(change { UsageRecord.count })

        expect(response).to have_http_status(502)
        expect(json["error"]).to eq("run_failed")
        expect(json["message"]).to be_present
      end
    end

    # ===================================================================
    # 認証・認可
    # ===================================================================
    context "scope が read だけのトークン" do
      let(:scopes) { %w[read] }

      it "403 insufficient_scope" do
        expect { post_run(message: message) }.not_to(change { UsageRecord.count })

        expect(response).to have_http_status(403)
        expect(json["error"]).to eq("insufficient_scope")
      end
    end

    it "未認証は 401" do
      post_run(headers: {}, message: message)

      expect(response).to have_http_status(401)
    end

    # ===================================================================
    # 同時実行（トークンあたり 1 本）
    # ===================================================================
    describe "同時実行の制限" do
      it "他のセッションがロックを握っている間は 429 concurrent_run" do
        expect do
          with_foreign_lock(lock_name) { post_run(message: message) }
        end.not_to(change { UsageRecord.count })

        expect(response).to have_http_status(429)
        expect(json["error"]).to eq("concurrent_run")
      end

      it "ロックが解放されれば実行できる" do
        with_foreign_lock(lock_name) { post_run(message: message) }
        expect(response).to have_http_status(429)

        expect { post_run(message: message) }.to change { UsageRecord.count }.by(1)
        expect(response).to have_http_status(200)
      end
    end
  end

  # ロックは MySQL の接続（セッション）単位なので、リクエストを処理する接続と
  # は別の接続で握る必要がある（同じ接続だと再取得できてしまう）。
  def with_foreign_lock(name)
    client = Mysql2::Client.new(foreign_connection_options)
    quoted = "'#{client.escape(name)}'"
    acquired = client.query("SELECT GET_LOCK(#{quoted}, 0)").first
    yield if acquired.values.first.to_i == 1
  ensure
    client&.query("SELECT RELEASE_LOCK(#{quoted})")
    client&.close
  end

  def foreign_connection_options
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    {
      host: config[:host],
      username: config[:username],
      password: config[:password].to_s,
      database: config[:database]
    }
  end
end
