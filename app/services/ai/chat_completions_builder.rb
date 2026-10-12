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

    # Tone instructions mapped from the client-side tone setting.
    TONE_INSTRUCTIONS = {
      "polite" => "丁寧な敬語で応答してください。",
      "casual" => "カジュアルな話し言葉で応答してください。",
      "professional" => "ビジネス向けのフォーマルな文体で応答してください。",
      "friendly" => "親しみやすくフレンドリーな口調で応答してください。"
    }.freeze

    # Output length instructions mapped from the client-side length setting.
    LENGTH_INSTRUCTIONS = {
      "short" => "回答は簡潔に、2〜3文程度でまとめてください。",
      "standard" => nil, # default — no extra instruction
      "long" => "回答は詳細に、背景説明や具体例を含めてください。"
    }.freeze

    def initialize(chat_session, settings = nil)
      @chat_session = chat_session
      @settings = settings.is_a?(Hash) ? settings : {}
    end

    # Builds the messages array for the AI provider.
    #
    # The system message is always first (role: "system").
    # User/assistant messages follow in chronological order.
    #
    # @return [Array<Hash>] messages array with role and content keys
    def build
      messages = []

      system_text = build_system_prompt
      if system_text.present?
        messages << { role: "system", content: system_text }
      end

      history_messages.each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages
    end

    private

    # Combines the session's system prompt with tone/length directives
    # derived from the user's execution settings.
    def build_system_prompt
      parts = [@chat_session.system_prompt]

      tone = @settings["tone"]
      parts << TONE_INSTRUCTIONS[tone] if TONE_INSTRUCTIONS.key?(tone)

      length = @settings["output_length"]
      length_text = LENGTH_INSTRUCTIONS[length]
      parts << length_text if length_text

      parts.compact_blank.join("\n\n")
    end

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
