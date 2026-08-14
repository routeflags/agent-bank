# frozen_string_literal: true

# Factory for selecting the appropriate AI provider adapter.
#
# Resolves a Listing's default AI model and returns the matching
# adapter (OpenAI or Anthropic) based on the provider's slug.
#
# Usage:
#   adapter = Ai::ProviderFactory.for(listing)
#   adapter.stream(messages) { |chunk| ... }
module Ai
  class ProviderFactory
    # Mapping from provider slug to adapter class.
    # Add new providers here as they are supported.
    ADAPTER_MAP = {
      "openai" => OpenAiAdapter,
      "anthropic" => AnthropicAdapter
    }.freeze

    # Raised when a listing has no default AI model configured,
    # or when the provider is not supported.
    class ProviderNotConfiguredError < StandardError; end

    # Returns the appropriate adapter for the given listing.
    #
    # Resolution flow:
    #   1. Find the ListingAiModel with is_default: true for this listing
    #   2. Resolve the AiModel and its AiProvider
    #   3. Select the adapter class by provider slug
    #
    # @param listing [Listing] the listing to resolve the adapter for
    # @return [OpenAiAdapter, AnthropicAdapter]
    # @raise [ProviderNotConfiguredError] if no model or unsupported provider
    def self.for(listing)
      listing_ai_model = listing.listing_ai_models.defaults.first

      unless listing_ai_model
        raise ProviderNotConfiguredError,
          "No default AI model configured for listing #{listing.id}"
      end

      ai_model = listing_ai_model.ai_model
      provider = ai_model.ai_provider

      adapter_class = ADAPTER_MAP[provider.slug]

      unless adapter_class
        raise ProviderNotConfiguredError,
          "Unsupported AI provider: #{provider.slug} (supported: #{ADAPTER_MAP.keys.join(', ')})"
      end

      adapter_class.new(ai_model)
    end
  end
end
