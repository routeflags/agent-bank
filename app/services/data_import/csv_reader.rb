# frozen_string_literal: true

require "csv"

module DataImport
  # CSV を読み、ヘッダー検証と行の正規化だけを行う（ドメイン知識は持たない）。
  #
  # - 文字コード: UTF-8（BOM 付き可）。それ以外は InvalidFileError。
  # - ヘッダー: 前後の空白を除去し、小文字に正規化して照合する。
  # - 値: 前後の空白を除去し、空文字は nil にする。
  # - 行番号: CSV ファイル上の物理行番号（ヘッダー行 = 1）。エラー報告用。
  class CsvReader
    class InvalidFileError < StandardError; end

    Row = Struct.new(:line, :cells, keyword_init: true) do
      def [](name)
        cells[name]
      end
    end

    Table = Struct.new(:headers, :rows, :ignored_columns, keyword_init: true)

    UTF8_BOM = "\xEF\xBB\xBF".b.freeze

    def self.read(path, required:, optional: [])
      new(path, required: required, optional: optional).read
    end

    def initialize(path, required:, optional: [])
      @path = path.to_s
      @required = required.map { |name| normalize_name(name) }
      @optional = optional.map { |name| normalize_name(name) }
    end

    def read
      csv = CSV.new(read_text, headers: true)
      first_data_row = csv.shift
      column_map = build_column_map(csv.headers)
      validate_headers!(column_map.keys)

      Table.new(
        headers: column_map.keys,
        rows: build_rows(csv, column_map, first_data_row),
        ignored_columns: column_map.keys - (@required + @optional)
      )
    rescue CSV::MalformedCSVError => e
      raise InvalidFileError, "CSV の解析に失敗しました: #{e.message}"
    end

    private

    attr_reader :path, :required, :optional

    def read_text
      raise InvalidFileError, "ファイルが見つかりません: #{path}" unless File.file?(path)

      raw = File.binread(path)
      raw = raw.byteslice(UTF8_BOM.bytesize, raw.bytesize - UTF8_BOM.bytesize) if raw.start_with?(UTF8_BOM)
      raise InvalidFileError, "CSV が空です: #{path}" if raw.to_s.strip.empty?

      text = raw.force_encoding(Encoding::UTF_8)
      raise InvalidFileError, "UTF-8 として読み取れません（文字コードを確認してください）: #{path}" unless text.valid_encoding?

      text
    end

    def normalize_name(name)
      name.to_s.strip.downcase
    end

    # 正規化した列名 => CSV 上の実際の見出し。値の取り出しは実際の見出しで行う。
    def build_column_map(raw_headers)
      raise InvalidFileError, "見出し行がありません: #{path}" if raw_headers.nil? || raw_headers.empty?

      raw_headers.each_with_object({}) do |header, map|
        name = normalize_name(header)
        raise InvalidFileError, "見出し行に同じ列名が複数あります: #{name}" if map.key?(name)

        map[name] = header
      end
    end

    def validate_headers!(headers)
      missing = required - headers
      return if missing.empty?

      raise InvalidFileError, "必須の列がありません: #{missing.join(', ')}（実際の見出し: #{headers.join(', ')}）"
    end

    # CSV#shift で 1 行ずつ読み、`CSV#lineno`（直前に読んだ行の物理行番号）を行番号にする。
    # 引用符内の改行を含む行では「行の終わり」の行番号になる（エラー報告用なので十分）。
    def build_rows(csv, column_map, first_data_row)
      rows = []
      csv_row = first_data_row

      while csv_row
        row = build_row(csv_row, column_map, csv.lineno)
        rows << row if row
        csv_row = csv.shift
      end

      rows
    end

    def build_row(csv_row, column_map, line)
      cells = column_map.transform_values { |raw_header| normalize_value(csv_row[raw_header]) }
      return nil if cells.values.all?(&:nil?)

      Row.new(line: line, cells: cells)
    end

    def normalize_value(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
