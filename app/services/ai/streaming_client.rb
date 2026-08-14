# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Ai
  # Low-level HTTP client for SSE streaming from OpenAI and Anthropic APIs.
  #
  # Faraday v1.x buffers the entire response, so true SSE streaming
  # requires raw Net::HTTP with chunked reading. This client handles:
  #   - Chunked transfer encoding
  #   - SSE line parsing (data: ... \n\n)
  #   - Timeout management
  #   - Connection keep-alive
  #
  # Usage:
  #   client = Ai::StreamingClient.new(url: "https://api.openai.com/v1/chat/completions")
  #   client.post(headers: {...}, body: {...}) do |chunk|
  #     puts chunk  # each SSE data line
  #   end
  class StreamingClient
    class StreamingError < StandardError; end
    class TimeoutError < StreamingError; end
    class ConnectionError < StreamingError; end

    # @param url [String] full API endpoint URL
    # @param read_timeout [Integer] maximum time to wait for response chunks (seconds)
    # @param open_timeout [Integer] TCP connection timeout (seconds)
    def initialize(url:, read_timeout: 120, open_timeout: 10)
      @uri = URI.parse(url)
      @read_timeout = read_timeout
      @open_timeout = open_timeout
    end

    # Sends a POST request and yields SSE data lines as they arrive.
    #
    # The block receives raw SSE data strings (without the "data: " prefix).
    # For OpenAI, each chunk is a JSON string like:
    #   {"choices":[{"delta":{"content":"Hello"}}]}
    # For Anthropic, each chunk is a JSON string like:
    #   {"type":"content_block_delta","delta":{"text":"Hello"}}
    #
    # @param headers [Hash] HTTP headers (Authorization, Content-Type, etc.)
    # @param body [Hash] request body (will be JSON-encoded)
    # @yield [data] each SSE data line (String)
    # @return [void]
    # @raise [StreamingError] on connection or read errors
    def post(headers:, body:, &block)
      http = build_http
      request = build_request(headers, body)

      response = http.request(request)

      case response
      when Net::HTTPSuccess
        parse_sse_stream(response, &block)
      when Net::HTTPRedirection
        raise ConnectionError, "Redirect to #{response["location"]} not supported"
      else
        raise StreamingError, "HTTP #{response.code}: #{response.message}"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "Read timeout: #{e.message}"
    rescue Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED => e
      raise ConnectionError, "Connection failed: #{e.message}"
    rescue IOError => e
      raise StreamingError, "IO error: #{e.message}"
    end

    private

    # Builds the Net::HTTP object with timeout settings.
    #
    # @return [Net::HTTP]
    def build_http
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == "https")
      http.read_timeout = @read_timeout
      http.open_timeout = @open_timeout
      http
    end

    # Builds the Net::HTTP::Post request with headers and body.
    #
    # @param headers [Hash]
    # @param body [Hash]
    # @return [Net::HTTP::Post]
    def build_request(headers, body)
      request = Net::HTTP::Post.new(@uri.request_uri)
      headers.each { |key, value| request[key] = value }
      request.body = body.to_json
      request
    end

    # Parses the SSE stream from the HTTP response.
    #
    # SSE format:
    #   data: {"chunk":"content"}\n\n
    #   data: [DONE]\n\n
    #
    # Each "data: " line (except [DONE]) is yielded to the block.
    #
    # @param response [Net::HTTPResponse]
    # @yield [data] each SSE data line
    def parse_sse_stream(response, &block)
      return unless block_given?

      buffer = ""
      stream_done = false

      response.read_body do |chunk|
        break if stream_done
        buffer += chunk

        # Process complete lines (delimited by \n)
        while (line_end = buffer.index("\n"))
          line = buffer.slice!(0, line_end + 1).strip
          next if line.empty?

          if line.start_with?("data: ")
            data = line[6..] # Remove "data: " prefix
            if data == "[DONE]"
              stream_done = true
              break
            end

            yield data
          end
          # Ignore event:, id:, retry: lines and comments
        end
      end

      # Process any remaining data in the buffer (only if stream didn't end with [DONE])
      unless stream_done || buffer.strip.empty?
        remaining = buffer.strip
        if remaining.start_with?("data: ")
          data = remaining[6..]
          yield data unless data == "[DONE]"
        end
      end
    end
  end
end
