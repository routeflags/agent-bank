# frozen_string_literal: true

module DataImport
  # インポート結果を「1 行 1 イベント + 最後にサマリ」で書き出す。
  # パスワードは結果に含めない方針なので、ここでも出力しない。
  class ConsoleReporter
    def initialize(io: $stdout)
      @io = io
    end

    def report(result, label:, commit:, on_conflict:)
      io.puts "#{label}インポート: #{commit ? '実書き込み' : 'ドライラン'}（ON_CONFLICT=#{on_conflict}）"
      io.puts "未対応の列は無視しました: #{result.ignored_columns.join(', ')}" if result.ignored_columns.any?

      result.created.each { |entry| io.puts "#{prefix(entry.line)} 作成: #{entry.label}" }
      result.updated.each { |entry| io.puts "#{prefix(entry.line)} 更新: #{entry.label}" }
      result.skipped.each { |entry| io.puts "#{prefix(entry.line)} スキップ: #{entry.label} — #{entry.reason}" }
      result.errors.each { |message| io.puts "#{prefix(message.line)} エラー: #{message.message}" }
      result.warnings.each { |message| io.puts "#{prefix(message.line)} 警告: #{message.message}" }

      io.puts "---"
      io.puts(dry_run_note) unless commit
      io.puts result.summary_line
      result
    end

    private

    attr_reader :io

    def prefix(line)
      line ? "[行#{line}]" : "[--]"
    end

    def dry_run_note
      "※ ドライランです。書き込みは行っていません（実行するには COMMIT=1 を付けてください）"
    end
  end
end
