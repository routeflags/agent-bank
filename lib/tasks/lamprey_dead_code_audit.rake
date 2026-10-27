# frozen_string_literal: true

# Issue #60 Phase B: デッドコード監査（レポートのみ。自動削除しない）。
#
# 使い方:
#   bin/rails 'lamprey:audit:dead_code'
#
# db/structure.sql のテーブル・列とコード側の参照を突き合わせ、参照ゼロの
# 列・テーブルを出力する。あわせて app/models / app/services / app/jobs /
# app/presenters の参照ゼロクラスを出力する。
#
# 使い方と判定基準は documents/guides/dead_code_audit.md を参照。
# 「参照ゼロ = 即削除」ではない。データ移行と依存の確認は別途行う。
module LampreyDeadCodeAudit
  # コード参照の探索範囲（Issue #60 の機械照合と同じ）。
  # app/helpers・app/view_utils・app/utils からの参照も数える。
  # 含めないと、ヘルパー経由でしか呼ばれないクラス（例: JsTranslations）を
  # 未参照と誤検知するため。除外するのは「監査対象」であって「参照元」ではない。
  CODE_ROOTS = %w[app lib config client/app].freeze
  # クラス監査の対象ディレクトリ。
  CLASS_TARGET_DIRS = %w[app/models app/services app/jobs app/presenters].freeze
  # クラス監査の対象から外すディレクトリ（除外リスト）。
  # Rails が名前解決・自動読み込み・文字列参照で読み込むため、参照ゼロ判定が
  # 誤検知になりやすい。参照元としては数える（CODE_ROOTS の注記を参照）。
  CLASS_TARGET_EXCLUDE_DIRS = %w[app/helpers app/view_utils app/utils].freeze
  # 探索から外すディレクトリ（依存物・生成物・履歴）。
  # db/migrate は履歴であり現行コードの参照ではないため数えない。
  # db/seeds.rb 等の投入口は別途目視確認する（ガイド参照）。
  SEARCH_EXCLUDE_PATTERN = %r{/(node_modules|vendor|tmp|log|\.git)/|\.(min\.js|map)\z}
  # フレームワークが名前で管理し、コード参照が無いのが正常なテーブル。
  FRAMEWORK_TABLES = %w[delayed_jobs schema_migrations ar_internal_metadata].freeze
  FRAMEWORK_TABLE_PREFIXES = %w[active_storage_].freeze

  module_function

  Result = Struct.new(:unused_columns, :unused_tables, :unused_classes, keyword_init: true)

  # 監査を実行し、結果を出力して返す。DB への書き込みは行わない。
  #
  # @param root [Pathname, String] Rails.root（spec から差し替え可能）
  # @param out [IO] 出力先（既定: $stdout）
  # @return [Result]
  def run(root: Rails.root, out: $stdout)
    root = Pathname(root)
    tables = tables_and_columns(root.join("db/structure.sql"))
    index = word_index(root)

    unused_columns = unused_columns_in(tables, index)
    unused_tables = unused_tables_in(tables, index)
    unused_classes = unused_classes_in(root, index)

    print_report(out, tables, unused_columns, unused_tables, unused_classes)
    Result.new(unused_columns: unused_columns, unused_tables: unused_tables, unused_classes: unused_classes)
  end

  # db/structure.sql から {テーブル名 => [列名]} を抽出する。
  def tables_and_columns(structure_sql_path)
    tables = {}
    current = nil
    File.foreach(structure_sql_path) do |line|
      if (match = line.match(/\ACREATE TABLE `([^`]+)`/))
        current = match[1]
        tables[current] = []
      elsif current && (match = line.match(/\A  `([^`]+)`/))
        # 2スペース＋バッククォートで始まるのは列定義。
        # KEY / CONSTRAINT / PRIMARY 等はここに来ない。
        tables[current] << match[1]
      end
    end
    tables
  end

  # {単語 => その単語を含むファイルの配列} の転置インデックスを作る。
  # 全ファイルを1回だけ読み、トークン単位の突き合わせを高速にする。
  def word_index(root)
    index = Hash.new { |hash, key| hash[key] = [] }
    code_files(root).each do |path|
      words = read_text(path).scan(/[A-Za-z0-9_]+/).uniq
      words.each { |word| index[word] << path }
    end
    index
  end

  # 参照探索の対象ファイル一覧。除外ディレクトリ配下は含めない。
  def code_files(root)
    files = []
    CODE_ROOTS.each do |dir|
      base = root.join(dir)
      next unless base.directory?

      Dir.glob(base.join("**/*").to_s).each do |path|
        next unless File.file?(path)
        next if excluded_path?(root, path)

        files << path
      end
    end
    files.sort
  end

  def excluded_path?(root, path)
    relative = Pathname(path).relative_path_from(Pathname(root)).to_s
    SEARCH_EXCLUDE_PATTERN.match?(relative)
  end

  # クラス監査の対象外パスかどうか（除外リスト）。
  def class_target_excluded?(root, path)
    relative = Pathname(path).relative_path_from(Pathname(root)).to_s
    CLASS_TARGET_EXCLUDE_DIRS.any? { |dir| relative == dir || relative.start_with?("#{dir}/") }
  end

  # ファイルを UTF-8 テキストとして読む。モデルの注釈ブロックは参照に数えない。
  def read_text(path)
    text = File.binread(path).force_encoding("UTF-8").scrub
    path.end_with?(".rb") ? strip_schema_annotation(text) : text
  end

  # モデル先頭の `# == Schema Information` 注釈ブロックを取り除く。
  # 注釈から始まり `#` で始まらない最初の行までを除去する。
  def strip_schema_annotation(text)
    stripped = []
    in_annotation = false
    text.each_line do |line|
      unless in_annotation
        if line.match?(/^# == Schema Information/)
          in_annotation = true
          next
        end
        stripped << line
        next
      end
      next if line.start_with?("#")

      in_annotation = false
      stripped << line
    end
    stripped.join
  end

  def unused_columns_in(tables, index)
    unused = []
    tables.each do |table, columns|
      # フレームワーク管理テーブル（active_storage_* 等）の列は
      # コード参照が無いのが正常なため監査しない。
      next if framework_table?(table)

      columns.each do |column|
        unused << "#{table}.#{column}" unless index.key?(column)
      end
    end
    unused.sort
  end

  def unused_tables_in(tables, index)
    tables.keys.reject { |table| framework_table?(table) || table_referenced?(table, index) }.sort
  end

  # テーブルは「モデルクラスへの言及」または「テーブル名そのものへの言及」が
  # あれば使用中とみなす。モデルファイル自体の定義も言及に含まれる。
  def table_referenced?(table, index)
    return true if index.key?(table)

    index.key?(table.singularize.camelize)
  end

  def framework_table?(table)
    FRAMEWORK_TABLES.include?(table) || FRAMEWORK_TABLE_PREFIXES.any? { |prefix| table.start_with?(prefix) }
  end

  def unused_classes_in(root, index)
    unused = []
    class_targets(root).each do |const_path, defining_file|
      referencing = class_name_variants(const_path).flat_map { |name| index[name] }.uniq
      referencing -= [defining_file]
      unused << const_path if referencing.empty?
    end
    unused.sort
  end

  # クラス参照の表記ゆれを吸収する。
  # has_many :chat_attachments / transaction.shipping_address のように
  # 定数名ではなく複数形・スネークケースで参照されるのが Rails の流儀のため。
  def class_name_variants(const_path)
    basename = const_path.split("::").last
    [basename, basename.underscore, basename.tableize].uniq
  end

  # [[定数パス, 定義ファイル]] の一覧。concerns 配下は名前空間に含めない
  # （Rails の concerns はトップレベルの定数として読み込まれる）。
  def class_targets(root)
    targets = []
    CLASS_TARGET_DIRS.each do |dir|
      base = root.join(dir)
      next unless base.directory?

      Dir.glob(base.join("**/*.rb").to_s).sort.each do |path|
        next if class_target_excluded?(root, path)

        relative = Pathname(path).relative_path_from(Pathname(base)).to_s
        segments = relative.delete_suffix(".rb").split("/")
        segments.shift if segments.first == "concerns"
        targets << [segments.map { |segment| segment.camelize }.join("::"), path]
      end
    end
    targets
  end

  def print_report(out, tables, unused_columns, unused_tables, unused_classes)
    total_columns = tables.values.sum(&:size)
    out.puts "[lamprey:audit:dead_code] デッドコード監査レポート（Issue #60。削除はしない）"
    out.puts "  対象: #{tables.size} テーブル・#{total_columns} 列"
    out.puts ""
    out.puts "## 参照ゼロの列（#{unused_columns.size} 件）"
    if unused_columns.empty?
      out.puts "  なし"
    else
      unused_columns.each { |column| out.puts "  - #{column}" }
    end
    out.puts ""
    out.puts "## 参照ゼロのテーブル（#{unused_tables.size} 件）"
    if unused_tables.empty?
      out.puts "  なし"
    else
      unused_tables.each { |table| out.puts "  - #{table}" }
    end
    out.puts ""
    out.puts "## 参照ゼロクラス（#{unused_classes.size} 件）"
    if unused_classes.empty?
      out.puts "  なし"
    else
      unused_classes.each { |klass| out.puts "  - #{klass}" }
    end
    out.puts ""
    out.puts "判定基準・除外リストは documents/guides/dead_code_audit.md を参照。"
    out.puts "「参照ゼロ = 即削除」ではない。データ移行と依存の確認は別途行うこと。"
  end
end

namespace :lamprey do
  namespace :audit do
    desc "参照ゼロの列・テーブル・クラスをレポートする（削除はしない。Issue #60）"
    task dead_code: :environment do
      LampreyDeadCodeAudit.run
    end
  end
end
