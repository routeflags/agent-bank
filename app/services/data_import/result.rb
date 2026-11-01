# frozen_string_literal: true

module DataImport
  # インポート 1 回分の結果。書き込みはせず、行ごとのイベントと集計だけを持つ。
  #
  # created / updated / skipped は Entry（行番号・ラベル・レコード）、
  # errors / warnings は Message（行番号・メッセージ）の配列。
  #
  # ドライランでも実書き込みでも同じ形を返す（違うのは書き込んだかどうかだけ）。
  class Result
    Entry = Struct.new(:line, :label, :record, :reason, keyword_init: true) do
      def to_s
        prefix = line ? "行#{line}" : "-"
        reason ? "[#{prefix}] #{label} — #{reason}" : "[#{prefix}] #{label}"
      end
    end

    Message = Struct.new(:line, :message, keyword_init: true) do
      def to_s
        line ? "[行#{line}] #{message}" : message.to_s
      end
    end

    attr_reader :created, :updated, :skipped, :errors, :warnings, :ignored_columns

    def initialize(ignored_columns: [])
      @created = []
      @updated = []
      @skipped = []
      @errors = []
      @warnings = []
      @ignored_columns = ignored_columns
    end

    def add_created(line:, label:, record: nil)
      @created << Entry.new(line: line, label: label, record: record)
      self
    end

    def add_updated(line:, label:, record: nil)
      @updated << Entry.new(line: line, label: label, record: record)
      self
    end

    def add_skipped(line:, label:, reason: nil, record: nil)
      @skipped << Entry.new(line: line, label: label, record: record, reason: reason)
      self
    end

    def add_error(line:, message:, label: nil)
      @errors << Message.new(line: line, message: label ? "#{label}: #{message}" : message)
      self
    end

    def add_warning(line:, message:)
      @warnings << Message.new(line: line, message: message)
      self
    end

    def summary
      {
        created: created.size,
        updated: updated.size,
        skipped: skipped.size,
        errors: errors.size,
        warnings: warnings.size
      }
    end

    def success?
      errors.empty?
    end

    def total
      created.size + updated.size + skipped.size + errors.size
    end

    def summary_line
      s = summary
      "作成: #{s[:created]} / 更新: #{s[:updated]} / スキップ: #{s[:skipped]} / " \
        "エラー: #{s[:errors]} / 警告: #{s[:warnings]}"
    end
  end
end
