# frozen_string_literal: true

# OpenAI API adapter for chat completions with streaming support.
#
# Uses Faraday v1.x to call the OpenAI Chat Completions API.
# Streams SSE chunks via a block callback, allowing the caller
# (PersonaExecutorJob) to broadcast each chunk through Action Cable.
#
# Usage:
#   adapter = Ai::OpenAiAdapter.new(ai_model)
#   result = adapter.stream(messages) do |chunk|
#     ActionCable.server.broadcast(channel, chunk)
#   end
#   result.input_tokens  # => 42
#   result.output_tokens # => 17
module Ai
  class OpenAiAdapter
    include Ai::ConnectionHelper

    # Struct for returning token usage from the API response.
    Usage = Struct.new(:input_tokens, :output_tokens, keyword_init: true)

    # Raised when the OpenAI API returns an error response.
    class ApiError < StandardError; end

    DEFAULT_BASE_URL = "https://api.openai.com/v1".freeze

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

    # Sends a chat completion request to OpenAI with true SSE streaming.
    #
    # Uses Net::HTTP for chunked reading (Faraday v1.x buffers the entire
    # response). Each SSE data chunk is parsed and yielded to the block.
    # The complete content and usage are accumulated and returned after
    # the stream ends.
    #
    # @param messages [Array<Hash>] messages array (role + content)
    # @yield [chunk] each streamed chunk { content: String, finish_reason: String }
    # @return [Usage] token usage from the response
    # @raise [ApiError] on non-200 responses or missing API key
    def stream(messages)
      api_key = @provider.api_key
      raise ApiError, "API key not configured for provider #{@provider.slug}" unless api_key.present?

      @accumulated_content = ""
      finish_reason = nil

      client = @streaming_client_class.new(url: "#{base_url}/chat/completions")
      client.post(
        headers: {
          "Authorization" => "Bearer #{api_key}",
          "Content-Type" => "application/json"
        },
        body: build_request_body(messages, stream: true)
      ) do |data|
        parsed = parse_chunk(data)
        next unless parsed

        # OpenAI sends usage in the final chunk (when stream_options.include_usage)
        if parsed[:usage]
          usage_data = parsed[:usage]
          @last_usage = Usage.new(
            input_tokens: usage_data[:prompt_tokens] || 0,
            output_tokens: usage_data[:completion_tokens] || 0
          )
          next
        end

        # Extract delta content from choices
        choice = parsed.dig(:choices, 0) || {}
        delta = choice[:delta] || {}
        content = delta[:content]

        if choice[:finish_reason]
          finish_reason = choice[:finish_reason]
        end

        if content&.present?
          @accumulated_content += content
          yield({ content: content, finish_reason: finish_reason }) if block_given?
        end
      end

      # Fallback: estimate usage if not provided in stream
      @last_usage ||= Usage.new(
        input_tokens: 0,
        output_tokens: estimate_tokens(@accumulated_content)
      )

      @last_usage
    rescue Ai::StreamingClient::StreamingError => e
      raise ApiError, "OpenAI streaming error: #{e.message}"
    end

    # Sends a synchronous (non-streaming) chat completion request.
    #
    # @param messages [Array<Hash>] messages array (role + content)
    # @return [Hash] { content: String, usage: Usage }
    # @raise [ApiError] on non-200 responses or missing API key
    def sync(messages)
      api_key = @provider.api_key
      raise ApiError, "API key not configured for provider #{@provider.slug}" unless api_key.present?

      response = connection.post do |req|
        req.url "/chat/completions"
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.headers["Content-Type"] = "application/json"
        req.body = build_request_body(messages, stream: false)
      end

      unless response.success?
        Rails.logger.debug("[OpenAI] Full error response: #{response.body}") if Rails.logger.debug?
        raise ApiError, "OpenAI API error (#{response.status})"
      end

      body = JSON.parse(response.body)
      choice = body.dig("choices", 0) || {}
      message_content = choice.dig("message", "content") || ""
      usage = body.dig("usage") || {}

      {
        content: message_content,
        usage: Usage.new(
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0
        )
      }
    end

    private

    # Builds the Faraday connection with timeout settings.
    #
    # @return [Faraday::Connection]
    def connection
      @connection ||= build_connection(base_url)
    end

    def base_url
      @provider.base_url.presence || DEFAULT_BASE_URL
    end

    # Builds the JSON request body for OpenAI chat completions.
    #
    # @param messages [Array<Hash>]
    # @param stream [Boolean]
    # @return [String] JSON-encoded body
    def build_request_body(messages, stream: true)
      body = {
        model: @ai_model.model_id,
        messages: messages,
        max_tokens: @ai_model.max_tokens || 4096,
        stream: stream
      }

      # Request usage statistics in streaming mode
      if stream
        body[:stream_options] = { include_usage: true }
      end

      body.to_json
    end

    # Parses a single SSE data chunk from OpenAI's streaming response.
    #
    # OpenAI SSE format:
    #   {"id":"...","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}
    #   {"id":"...","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5}}
    #
    # @param data [String] raw SSE data line (JSON string)
    # @return [Hash, nil] parsed JSON hash or nil
    def parse_chunk(data)
      JSON.parse(data, symbolize_names: true)
    rescue JSON::ParserError
      Rails.logger.debug("[OpenAI] Failed to parse SSE chunk: #{data.truncate(100)}")
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
