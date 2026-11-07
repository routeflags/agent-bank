# frozen_string_literal: true

# Issue #148（第 1 段）: チャットの実行経路を記録する。
#
#   web — ブラウザのチャット UI（従来の唯一の経路。既存行の既定値）
#   mcp — 外部クライアント（#144 の実行 API / MCP ツール）
#
# ジョブ（PersonaExecutorJob）がこの値を `usage_records.channel` に写す。
# 経路別の集計は `lamprey:usage_by_channel` を参照。
class AddChannelToChatSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_sessions, :channel, :string, null: false, default: "web"
  end
end
