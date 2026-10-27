# frozen_string_literal: true

module Ai
  # Raised when an AI provider returns an error response.
  #
  # Carries the HTTP status and the provider-native error code so callers
  # can tell terminal failures (billing exhausted, bad credentials) apart
  # from transient ones. Without them every provider problem reached the
  # user as the same "try again" message, which hid an empty API balance
  # behind what looked like a broken chat.
  #
  # Both adapters raise this type: Ai::OpenAiAdapter::ApiError and
  # Ai::AnthropicAdapter::ApiError are aliases kept for readability.
  class ProviderError < StandardError
    attr_reader :status, :code

    # @param message [String, nil] human readable description
    # @param status [Integer, nil] HTTP status from the provider
    # @param code [String, nil] provider error code/type (e.g. "credit_balance_exhausted")
    def initialize(message = nil, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end
  end
end
