# frozen_string_literal: true

# Decides whether an assistant message is a "result" (artifact) worth
# showing in the chat's right-hand Result panel (DESIGN.md §13).
#
# The design doc is explicit that the special result display must NOT be
# applied to every answer ("通常の回答すべてに適用しない"), so detection is
# deliberately conservative: only messages that clearly carry a deliverable
# are flagged.
#
# An assistant message counts as a result when either:
#   1. It contains a fenced code block (a code artifact the user can copy),
#      or
#   2. It is a structured long-form document: markdown headers plus enough
#      body text (a report, guide, or analysis).
#
# Short conversational replies, lists without code, and Q&A answers are
# normal messages, not results.
#
# Usage:
#   Ai::ResultDetector.result?(message.content)  # => true / false
module Ai
  class ResultDetector
    # Fenced code block (```lang ... ```).
    CODE_FENCE = /```[\s\S]*?```/

    # Markdown header lines (## Heading etc.).
    # \# escapes the hash so Ruby does not treat #{...} as interpolation.
    MARKDOWN_HEADER = /^[ \t]{0,3}\#{1,6}[ \t]+\S/

    # Minimum characters for the "structured document" path. Keeps short
    # prose answers out of the result panel.
    MIN_DOCUMENT_LENGTH = 300

    # Minimum distinct headers required to treat text as a document.
    MIN_HEADERS = 2

    def self.result?(content)
      new(content).result?
    end

    def initialize(content)
      @content = content.to_s
    end

    def result?
      return false if @content.strip.empty?

      code_artifact? || document_artifact?
    end

    private

    def code_artifact?
      @content.match?(CODE_FENCE)
    end

    def document_artifact?
      return false if @content.length < MIN_DOCUMENT_LENGTH

      @content.scan(MARKDOWN_HEADER).length >= MIN_HEADERS
    end
  end
end
