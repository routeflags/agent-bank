# frozen_string_literal: true

# Issue #148（第 1 段）: 利用記録に実行経路を持たせる。
#
# 値は `chat_sessions.channel` をそのまま写す（PersonaExecutorJob）。
# `usage_records` は chat_session_id を持たないため、集計時はここで経路が
# 分かる必要がある。
#
# インデックスは「経路 × 期間」で COUNT / SUM する想定の複合
# （`[channel, created_at]`）。先頭を channel にして経路を絞ってから
# 期間で走査できるようにする。
class AddChannelToUsageRecords < ActiveRecord::Migration[8.1]
  def change
    change_table :usage_records, bulk: true do |t|
      t.string :channel, null: false, default: "web"
      t.index %i[channel created_at]
    end
  end
end
