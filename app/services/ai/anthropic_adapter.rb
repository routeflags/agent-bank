# frozen_string_literal: true

# Anthropic API adapter for chat completions with streaming support.
#
# Uses Faraday v1.x to call the Anthropic Messages API.
# Anthropic's API differs from OpenAI:
#   - System prompt is a top-level `system` parameter (not in messages)
#   - Messages alternate between user/assistant roles only
#   - Streaming uses SSE with "content_block_delta" events
#
# Usage:
#   adapter = Ai::AnthropicAdapter.new(ai_model)
#   result = adapter.stream(messages) do |chunk|
#     ActionCable.server.broadcast(channel, chunk)
#   end
#   result.input_tokens  # => 42
#   result.output_tokens # => 17
module Ai
  class AnthropicAdapter
    include Ai::ConnectionHelper

    # Struct for returning token usage from the API response.
    Usage = Struct.new(:input_tokens, :output_tokens, keyword_init: true)

    # Raised when the Anthropic API returns an error response.
    class ApiError < StandardError; end

    DEFAULT_BASE_URL = "https://api.anthropic.com".freeze
    API_VERSION = "2023-06-01".freeze

    attr_reader :ai_model, :accumulated_content

    def initialize(ai_model, streaming_client: nil)
      @ai_model = ai_model
      @provider = ai_model.ai_provider
      @last_usage = nil
      @accumulated_content = ""
      @streaming_client_class = streaming_client || Ai::StreamingClient
    end

    # Returns the usage from the most recent API call.
    #
    # @return [Usage, nil]
    def last_usage
      @last_usage
    end

    # Sends a messages request to Anthropic with true SSE streaming.
    #
    # Uses Net::HTTP for chunked reading (Faraday v1.x buffers the entire
    # response). Each SSE data chunk is parsed and yielded to the block.
    # Anthropic's SSE format uses event types:
    #   - content_block_delta: incremental text content
    #   - message_delta: stop reason and usage
    #   - message_stop: end of message
    #
    # @param messages [Array<Hash>] messages array (role + content)
    # @yield [chunk] each streamed chunk { content: String, type: String }
    # @return [Usage] token usage from the response
    # @raise [ApiError] on non-200 responses or missing API key
    def stream(messages)
      api_key = @provider.api_key
      raise ApiError, "API key not configured for provider #{@provider.slug}" unless api_key.present?

      system_text, api_messages = extract_system_and_messages(messages)
      @accumulated_content = ""

      client = @streaming_client_class.new(url: "#{base_url}/v1/messages")
      client.post(
        headers: {
          "x-api-key" => api_key,
          "anthropic-version" => API_VERSION,
          "Content-Type" => "application/json"
        },
        body: build_request_body(api_messages, system_text, stream: true)
      ) do |data|
        event = parse_event(data)
        next unless event

        case event[:type]
        when "content_block_delta"
          text = event.dig(:delta, :text)
          if text.present?
            @accumulated_content += text
            yield({ content: text, type: "content_block_delta" }) if block_given?
          end
        when "message_delta"
          # Extract usage from the final message_delta event
          usage_data = event[:usage]
          if usage_data
            @last_usage = Usage.new(
              input_tokens: usage_data[:input_tokens] || 0,
              output_tokens: usage_data[:output_tokens] || 0
            )
          end
        when "message_stop"
          yield({ content: "", type: "message_stop" }) if block_given?
        end
      end

      # Fallback usage if not provided in stream
      @last_usage ||= Usage.new(
        input_tokens: 0,
        output_tokens: estimate_tokens(@accumulated_content)
      )

      @last_usage
    rescue Ai::StreamingClient::StreamingError => e
      raise ApiError, "Anthropic streaming error: #{e.message}"
    end

    # Sends a synchronous (non-streaming) messages request.
    #
    # @param messages [Array<Hash>] messages array (role + content)
    # @return [Hash] { content: String, content_blocks: Array<String>, usage: Usage }
    # @raise [ApiError] on non-200 responses or missing API key
    def sync(messages)
      api_key = @provider.api_key
      raise ApiError, "API key not configured for provider #{@provider.slug}" unless api_key.present?

      system_text, api_messages = extract_system_and_messages(messages)

      response = connection.post do |req|
        req.url "/v1/messages"
        req.headers["x-api-key"] = api_key
        req.headers["anthropic-version"] = API_VERSION
        req.headers["Content-Type"] = "application/json"
        req.body = build_request_body(api_messages, system_text, stream: false)
      end

      unless response.success?
        Rails.logger.debug("[Anthropic] Full error response: #{response.body}") if Rails.logger.debug?
        raise ApiError, "Anthropic API error (#{response.status})"
      end

      body = JSON.parse(response.body)
      content_blocks = body.dig("content") || []
      message_content = content_blocks
        .select { |b| b["type"] == "text" }
        .map { |b| b["text"] }
        .join

      usage = body.dig("usage") || {}

      {
        content: message_content,
        content_blocks: content_blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] },
        usage: Usage.new(
          input_tokens: usage["input_tokens"] || 0,
          output_tokens: usage["output_tokens"] || 0
        )
      }
    end

    private

    # Extracts the system prompt and remaining messages for Anthropic's format.
    #
    # Anthropic requires:
    #   - System prompt as a top-level `system` parameter
    #   - Messages with only user/assistant roles
    #
    # @param messages [Array<Hash>] full messages array (may include system)
    # @return [Array(String, Array<Hash>)] system_text, api_messages
    def extract_system_and_messages(messages)
      system_text = nil
      api_messages = messages.reject do |msg|
        if msg[:role] == "system"
          system_text = msg[:content]
          true
        else
          false
        end
      end

      [system_text, api_messages]
    end

    # Builds the Faraday connection with timeout settings.
    #
    # @return [Faraday::Connection]
    def connection
      @connection ||= build_connection(base_url)
    end

    def base_url
      @provider.base_url.presence || DEFAULT_BASE_URL
    end

    # Builds the JSON request body for Anthropic messages API.
    #
    # @param messages [Array<Hash>]
    # @param system_text [String, nil]
    # @param stream [Boolean]
    # @return [String] JSON-encoded body
    def build_request_body(messages, system_text, stream: true)
      body = {
        model: @ai_model.model_id,
        max_tokens: @ai_model.max_tokens || 4096,
        messages: messages,
        stream: stream
      }

      body[:system] = system_text if system_text.present?

      body.to_json
    end

    # Parses a single SSE data event from Anthropic's streaming response.
    #
    # Anthropic SSE format:
    #   {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
    #   {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":10,"output_tokens":5}}
    #   {"type":"message_stop"}
    #
    # @param data [String] raw SSE data line (JSON string)
    # @return [Hash, nil] parsed event hash or nil
    def parse_event(data)
      JSON.parse(data, symbolize_names: true)
    rescue JSON::ParserError
      Rails.logger.debug("[Anthropic] Failed to parse SSE event: #{data.truncate(100)}")
      nil
    end

    # Rough token estimation (4 chars ≈ 1 token for English).
    #
    # @param text [String]
    # @return [Integer]
    def estimate_tokens(text)
      (text.length / 4.0).ceil
    end
  end
end
