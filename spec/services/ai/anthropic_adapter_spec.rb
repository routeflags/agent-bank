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

  describe "#accumulated_content" do
    it "is empty string after initialization" do
      adapter = described_class.new(ai_model)
      expect(adapter.accumulated_content).to eq("")
    end
  end
end
