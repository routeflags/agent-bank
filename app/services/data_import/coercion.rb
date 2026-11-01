# frozen_string_literal: true

module DataImport
  # CSV のセル文字列を Ruby の値に変換する小さなヘルパー（両 importer の共通部）。
  module Coercion
    TRUE_VALUES = %w[1 true yes y on].freeze
    FALSE_VALUES = %w[0 false no n off].freeze

    module_function

    # 真偽値として解釈できれば true / false、できなければ nil。
    def boolean(value)
      text = value.to_s.strip.downcase
      return true if TRUE_VALUES.include?(text)
      return false if FALSE_VALUES.include?(text)

      nil
    end

    # 整数として解釈できれば Integer、できなければ nil（"1,000" や "12.5" は不可）。
    def integer(value)
      Integer(value.to_s.strip, 10, exception: false)
    end
  end
end
