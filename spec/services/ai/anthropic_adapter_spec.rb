# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ai::AnthropicAdapter do
  let(:ai_provider) do
    instance_double(
      AiProvider,
      slug: "anthropic",
      api_key: "test-api-key",
      base_url: nil
    )
  end
  let(:ai_model) do
    instance_double(
      AiModel,
      model_id: "claude-3-sonnet-20240229",
      max_tokens: 4096,
      ai_provider: ai_provider
    )
  end

  describe "#initialize" do
    it "accepts optional streaming_client parameter" do
      fake_client_class = Class.new
      adapter = described_class.new(ai_model, streaming_client: fake_client_class)
      expect(adapter.ai_model).to eq(ai_model)
    end

    it "defaults to Ai::StreamingClient when no streaming_client given" do
      adapter = described_class.new(ai_model)
      expect(adapter.ai_model).to eq(ai_model)
    end
  end

  describe "#stream の system パラメータ転送" do
    # Issue #57: Anthropic は system をメッセージ配列ではなくトップレベルで渡す。
    let(:sent_bodies) { [] }
    let(:capturing_client_class) do
      bodies = sent_bodies
      Class.new do
        define_method(:initialize) { |**| }
        define_method(:post) do |headers:, body:, &_block|
          bodies << JSON.parse(body)
        end
      end
    end
    let(:messages) do
      [
        { role: "system", content: "## 傾聴スキル\n- 相手の感情を言語化して返す" },
        { role: "user", content: "こんにちは" }
      ]
    end

    it "system ロールをトップレベルの system パラメータとして送る" do
      adapter = described_class.new(ai_model, streaming_client: capturing_client_class)
      adapter.stream(messages) { |_| }

      expect(sent_bodies.first["system"]).to eq("## 傾聴スキル\n- 相手の感情を言語化して返す")
    end

    it "メッセージ配列から system ロールを除去する" do
      adapter = described_class.new(ai_model, streaming_client: capturing_client_class)
      adapter.stream(messages) { |_| }

      sent = sent_bodies.first["messages"]
      expect(sent).to eq([{ "role" => "user", "content" => "こんにちは" }])
    end
  end

  describe "#stream の max_tokens 転送（Issue #105）" do
    # max_tokens は Anthropic の必須パラメータ。nil のときはモデルの最大出力値を送る。
    let(:sent_bodies) { [] }
    let(:capturing_client_class) do
      bodies = sent_bodies
      Class.new do
        define_method(:initialize) { |**| }
        define_method(:post) do |headers:, body:, &_block|
          bodies << JSON.parse(body)
        end
      end
    end
    let(:messages) { [{ role: "user", content: "こんにちは" }] }

    it "nil のときは @ai_model.max_tokens を送る" do
      adapter = described_class.new(ai_model, streaming_client: capturing_client_class)
      adapter.stream(messages, max_tokens: nil) { |_| }

      expect(sent_bodies.first["max_tokens"]).to eq(4096)
    end

    it "モデル固有の max_tokens を使う（ハードコードではない）" do
      large_model = instance_double(
        AiModel,
        model_id: "claude-3-5-sonnet-20241022",
        max_tokens: 8192,
        ai_provider: ai_provider
      )
      adapter = described_class.new(large_model, streaming_client: capturing_client_class)
      adapter.stream(messages, max_tokens: nil) { |_| }

      expect(sent_bodies.first["max_tokens"]).to eq(8192)
    end

    it "指定値があるときはそのまま送る" do
      adapter = described_class.new(ai_model, streaming_client: capturing_client_class)
      adapter.stream(messages, max_tokens: 20_000) { |_| }

      expect(sent_bodies.first["max_tokens"]).to eq(20_000)
    end
  end

  describe "#accumulated_content" do
    it "is empty string after initialization" do
      adapter = described_class.new(ai_model)
      expect(adapter.accumulated_content).to eq("")
    end
  end

  describe "#stream の stop_reason 伝達（Issue #63）" do
    # SSE イベント行をブロックに渡すだけの疑似ストリーミングクライアント。
    # 実送信はしない（外部 API への実送信は禁止）。
    let(:stub_client_class) do
      lines = sse_lines
      Class.new do
        define_method(:initialize) { |**| }
        define_method(:post) do |headers:, body:, &block|
          lines.each { |line| block.call(line) }
        end
      end
    end
    let(:request_messages) { [{ role: "user", content: "hi" }] }

    context "上限打ち切り（max_tokens）の場合" do
      let(:sse_lines) do
        [
          '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}',
          '{"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"input_tokens":10,"output_tokens":5}}',
          '{"type":"message_stop"}'
        ]
      end

      it "stop_reason max_tokens を last_finish_reason として保持する" do
        adapter = described_class.new(ai_model, streaming_client: stub_client_class)
        adapter.stream(request_messages) { |_| }

        expect(adapter.accumulated_content).to eq("Hello")
        expect(adapter.last_finish_reason).to eq("max_tokens")
        expect(adapter.last_usage.output_tokens).to eq(5)
      end
    end

    context "正常完結（end_turn）の場合" do
      let(:sse_lines) do
        [
          '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}',
          '{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":10,"output_tokens":3}}',
          '{"type":"message_stop"}'
        ]
      end

      it "stop_reason end_turn を保持する" do
        adapter = described_class.new(ai_model, streaming_client: stub_client_class)
        adapter.stream(request_messages) { |_| }

        expect(adapter.accumulated_content).to eq("Hi")
        expect(adapter.last_finish_reason).to eq("end_turn")
      end
    end
  end
end
