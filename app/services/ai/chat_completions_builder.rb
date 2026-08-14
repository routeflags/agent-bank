# frozen_string_literal: true

# Builds the messages array for AI chat completions.
#
# Converts a ChatSession's system_prompt (derived from Listing persona fields)
# and chat_messages history into a messages array suitable for both OpenAI
# and Anthropic API formats.
#
# Usage:
#   messages = Ai::ChatCompletionsBuilder.new(chat_session).build
#   # => [{ role: "system", content: "..." }, { role: "user", content: "..." }, ...]
module Ai
  class ChatCompletionsBuilder
    # Maximum number of recent messages to include in context.
    # Prevents exceeding context window limits for older sessions.
    MAX_HISTORY_MESSAGES = 50

    def initialize(chat_session)
      @chat_session = chat_session
    end

    # Builds the messages array for the AI provider.
    #
    # The system message is always first (role: "system").
    # User/assistant messages follow in chronological order.
    #
    # @return [Array<Hash>] messages array with role and content keys
    def build
      messages = []

      system_text = @chat_session.system_prompt
      if system_text.present?
        messages << { role: "system", content: system_text }
      end

      history_messages.each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages
    end

    private

    # Returns the recent chat messages in chronological order.
    # Caps to MAX_HISTORY_MESSAGES to avoid context overflow.
    #
    # @return [ActiveRecord::Relation] ordered chat messages
    def history_messages
      @chat_session.chat_messages
        .chronological
        .where(role: %w[user assistant])
        .limit(MAX_HISTORY_MESSAGES)
    end
  end
end
