# frozen_string_literal: true

require 'rails_helper'

# 利用記録（Issue #148 第 1 段）。
#
# `channel` は実行経路。既存行とブラウザのチャットは既定の web、外部クライアント
# （#144 の実行 API）は mcp。値は `PersonaExecutorJob` が
# `chat_sessions.channel` から写す（#144 の request spec で確認）。
RSpec.describe UsageRecord, type: :model do
  it "channel の既定値は web" do
    expect(UsageRecord.new.channel).to eq("web")
    expect(UsageRecord.create!.reload.channel).to eq("web")
  end

  it "channel を指定すればその値で記録できる" do
    expect(UsageRecord.create!(channel: "mcp").reload.channel).to eq("mcp")
  end
end
