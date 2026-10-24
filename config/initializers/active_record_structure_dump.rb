# frozen_string_literal: true

# MariaDB サーバーに MySQL 8 系の `mysqldump` を使うと、統計情報取得のため
# `information_schema.COLUMN_STATISTICS` を参照して失敗する。
#
#   1109: Unknown table 'column_statistics' in information_schema
#
# この場合 `db:schema:dump` が空の `db/structure.sql` を書き出してしまい、
# スキーマ定義が失われる。クライアントが対応しているときだけ統計取得を
# 無効化し、`bin/rails db:schema:dump` を素直に通す。
#
# MariaDB の `mariadb-dump` など対応していないクライアントではフラグを
# 付けない（未対応フラグで失敗するため）。
if Rails.application.config.active_record.schema_format == :sql
  require "active_record/tasks/database_tasks"

  mysqldump_help = `mysqldump --help 2>/dev/null`

  if mysqldump_help.include?("--column-statistics")
    ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = {
      mysql2: ["--column-statistics=0"]
    }
  end
end
