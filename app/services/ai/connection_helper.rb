# frozen_string_literal: true

module Ai
  # Builds Faraday connections with consistent timeout settings.
  # Included by OpenAiAdapter and AnthropicAdapter to avoid duplication.
  module ConnectionHelper
    private

    # Builds a Faraday connection with the given URL and timeout settings.
    #
    # @param url [String] the base URL for the API
    # @param timeout [Integer] total request timeout in seconds
    # @param open_timeout [Integer] TCP connection timeout in seconds
    # @return [Faraday::Connection]
    def build_connection(url, timeout: 120, open_timeout: 10)
      Faraday.new(url: url) do |faraday|
        faraday.options.timeout = timeout
        faraday.options.open_timeout = open_timeout
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
