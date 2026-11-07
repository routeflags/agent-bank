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

  # Issue #94 で cost_cents は decimal(14,2) になった。ここが `to_i` のままだと
  # 1 回 1 セント未満の原価が 0 に潰れ、原価の積み上げ（#122 の逆ザヤ監視）が
  # できない。少数 2 桁で残ることを固定する。
  describe "cost_cents（AI 原価・USD セント建て）" do
    def record_for(input_tokens:, output_tokens:, input_rate:, output_rate:)
      model = FactoryBot.create(
        :ai_model,
        ai_provider: FactoryBot.create(:ai_provider),
        cost_per_1k_input: input_rate,
        cost_per_1k_output: output_rate
      )
      UsageRecord.create!(
        ai_model: model,
        input_tokens: input_tokens,
        output_tokens: output_tokens
      )
    end

    it "1 セント未満の原価を 0 に潰さず小数 2 桁で残す" do
      # 100/1000*0.3 + 0/1000*0.3 = 0.03 USD = 3 セント。`to_i` 時代は
      # 0.03*100 = 3 で同じだが、より小さい値では 0 に潰れていた。
      record = record_for(
        input_tokens: 10, output_tokens: 0, input_rate: 0.3, output_rate: 0.3
      )

      expect(record.cost_cents.to_f).to eq(0.3)
    end

    it "セント単位の原価は 2 桁で四捨五入する" do
      # 100/1000*1.0 + 50/1000*2.0 = 0.2 USD = 20 セント。
      record = record_for(
        input_tokens: 100, output_tokens: 50, input_rate: 1.0, output_rate: 2.0
      )

      expect(record.cost_cents.to_f).to eq(20.0)
    end
  end
end
