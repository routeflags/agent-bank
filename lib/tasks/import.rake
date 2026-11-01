# frozen_string_literal: true

# CSV インポート経路（Issue #135）。
#
# 実装は app/services/data_import/ 側に切り出してあり、ここは薄いラッパー。
#
#   bin/rails "import:users[db/import/users.csv]"                 # ドライラン（既定）
#   COMMIT=1 bin/rails "import:users[db/import/users.csv]"        # 実書き込み
#   COMMIT=1 ON_CONFLICT=update bin/rails "import:listings[db/import/listings.csv]"
module ImportTaskSupport
  module_function

  def run(importer_class, path, label)
    abort "CSV のパスを指定してください（例: bin/rails \"import:users[db/import/users.csv]\"）" if path.to_s.strip.empty?

    commit = ENV["COMMIT"] == "1"
    on_conflict = ENV.fetch("ON_CONFLICT", "skip")

    result = importer_class.import(path, commit: commit, on_conflict: on_conflict)
    DataImport::ConsoleReporter.new(io: $stdout).report(result, label: label, commit: commit, on_conflict: on_conflict)

    exit 1 unless result.success?
  rescue DataImport::CsvReader::InvalidFileError, ArgumentError => e
    abort "インポートできませんでした: #{e.message}"
  end
end

namespace :import do
  desc "users.csv からユーザーを投入する（既定はドライラン、COMMIT=1 で実書き込み）"
  task :users, [:path] => :environment do |_task, args|
    ImportTaskSupport.run(DataImport::UserImporter, args[:path], "ユーザー")
  end

  desc "listings.csv から出品（ペルソナ）を投入する（既定はドライラン、COMMIT=1 で実書き込み）"
  task :listings, [:path] => :environment do |_task, args|
    ImportTaskSupport.run(DataImport::ListingImporter, args[:path], "出品")
  end
end
