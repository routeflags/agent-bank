# frozen_string_literal: true

# 利用記録に「誰の利用か」を持たせる（Issue #147）。
#
# 日次上限（`api_tokens.daily_cost_limit_cents`）は、当日の `channel = "mcp"` の
# `charge_cents` 合計で判定する。`usage_records` は `person_id` も
# `chat_session_id` も持たず、`credit_transactions` も請求額を利用記録へ結び付け
# ていないため、既存の列だけでは人単位に集計できなかった（`chat_sessions` は
# `person_id` を持つが、利用記録からセッションへ辿る列が無い）。
#
# 追加する列は nullable。既存行は帰属が不明なので埋めない（遡って数えない）。
# `people.id` は varchar(22) で UNIQUE ではないため DB レベルの FK は付けない
# （`chat_sessions` と同じ方針。整合性はアプリ層で担保する）。
class AddPersonIdToUsageRecords < ActiveRecord::Migration[8.1]
  def change
    change_table :usage_records, bulk: true do |t|
      t.string :person_id, limit: 22
      # 日次上限の判定は「ある人の・ある経路の・ある期間」で引くので、その順に張る。
      t.index %i[person_id channel created_at]
    end
  end
end
