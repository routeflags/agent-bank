# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ai::OpenAiAdapter do
  let(:ai_provider) do
    instance_double(
      AiProvider,
      slug: "openai",
      api_key: "test-api-key",
      base_url: nil
    )
  end
  let(:ai_model) do
    instance_double(
      AiModel,
      model_id: "gpt-4",
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

  describe "#accumulated_content" do
    it "is empty string after initialization" do
      adapter = described_class.new(ai_model)
      expect(adapter.accumulated_content).to eq("")
    end
  end

  describe "#stream の system ロール転送" do
    # Issue #57: スキルは system ロールで渡す。user 先頭埋め込みは不採用。
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

    it "messages の先頭を system ロールとしてそのまま送る" do
      adapter = described_class.new(ai_model, streaming_client: capturing_client_class)
      adapter.stream(messages) { |_| }

      sent = sent_bodies.first["messages"]
      expect(sent[0]).to eq({ "role" => "system", "content" => "## 傾聴スキル\n- 相手の感情を言語化して返す" })
    end

    it "user メッセージの先頭に指示を埋め込まない" do
      adapter = described_class.new(ai_model, streaming_client: capturing_client_class)
      adapter.stream(messages) { |_| }

      sent = sent_bodies.first["messages"]
      expect(sent[1]).to eq({ "role" => "user", "content" => "こんにちは" })
    end
  end

  describe "#stream の finish_reason 伝達（Issue #63）" do
    # SSE データ行をブロックに渡すだけの疑似ストリーミングクライアント。
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

    context "上限打ち切り（length）の場合" do
      let(:sse_lines) do
        [
          '{"id":"chatcmpl-1","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}',
          '{"id":"chatcmpl-1","choices":[{"delta":{},"finish_reason":"length"}]}',
          '{"id":"chatcmpl-1","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
        ]
      end

      it "content が空の最終チャンクでも finish_reason を保持する" do
        adapter = described_class.new(ai_model, streaming_client: stub_client_class)
        yielded = []
        adapter.stream([{ role: "user", content: "hi" }]) { |chunk| yielded << chunk }

        expect(adapter.accumulated_content).to eq("Hello")
        expect(adapter.last_finish_reason).to eq("length")
        expect(adapter.last_usage.output_tokens).to eq(5)
        # 空 content の終端チャンクは yield しない（空の stream_chunk を流さない）
        expect(yielded).to eq([{ content: "Hello", finish_reason: nil }])
      end
    end

    context "正常完結（stop）の場合" do
      let(:sse_lines) do
        [
          '{"id":"chatcmpl-1","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}',
          '{"id":"chatcmpl-1","choices":[{"delta":{},"finish_reason":"stop"}]}',
          '{"id":"chatcmpl-1","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":3}}'
        ]
      end

      it "finish_reason stop を保持する" do
        adapter = described_class.new(ai_model, streaming_client: stub_client_class)
        adapter.stream([{ role: "user", content: "hi" }]) { |_| }

        expect(adapter.accumulated_content).to eq("Hi")
        expect(adapter.last_finish_reason).to eq("stop")
      end
    end
  end

  describe "#stream のエラー" do
    let(:error_body) do
      '{"error":{"message":"You have no credits remaining.",' \
        '"type":"insufficient_quota","code":"credit_balance_exhausted"}}'
    end

    # StreamingClient が HTTP エラーを投げる状況を再現する。
    # ステータスと本文はエラーから分類できるように引き継がれる必要がある。
    let(:failing_client_class) do
      captured_body = error_body
      Class.new do
        define_method(:initialize) { |**| }
        define_method(:post) do |*_args, &_block|
          raise Ai::StreamingClient::StreamingError.new(
            "HTTP 429: Too Many Requests",
            status: 429,
            body: captured_body
          )
        end
      end
    end

    it "ステータスとプロバイダーのエラーコードを保持した ApiError を投げる" do
      adapter = described_class.new(ai_model, streaming_client: failing_client_class)

      expect {
        adapter.stream([{ role: "user", content: "hi" }]) { |_chunk| }
      }.to raise_error(Ai::OpenAiAdapter::ApiError) { |error|
        expect(error.status).to eq(429)
        expect(error.code).to eq("credit_balance_exhausted")
      }
    end
  end
end
