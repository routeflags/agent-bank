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

  describe "#accumulated_content" do
    it "is empty string after initialization" do
      adapter = described_class.new(ai_model)
      expect(adapter.accumulated_content).to eq("")
    end
  end
end
