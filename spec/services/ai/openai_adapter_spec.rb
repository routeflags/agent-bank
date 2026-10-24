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
