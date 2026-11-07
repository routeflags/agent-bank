# frozen_string_literal: true

require 'rails_helper'

# MCP 実行の日次上限（Issue #147）。
#
# - 対象は channel = mcp の charge_cents（請求額・円）だけ
# - 合計は人単位（同じ人が複数のトークンを持っていても同じ合計に入る）
# - 日界は JST 0 時
# - 上限はトークン（api_tokens.daily_cost_limit_cents）が持つ
RSpec.describe McpDailyLimit, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }
  let(:token) { APIToken.issue!(person: person, name: "MCP", scopes: %w[read run]).first }

  # 2026-02-01 09:00 JST = 2026-02-01 00:00 UTC
  let(:now) { jst("2026-02-01 09:00:00") }

  # 日界の検証用。JST の壁時計で時刻を作る。
  def jst(value)
    ActiveSupport::TimeZone["Asia/Tokyo"].parse(value)
  end

  def build_limit(person: self.person, token: self.token, now: self.now)
    McpDailyLimit.new(person: person, token: token, now: now)
  end

  # @param charge_cents [String, Numeric] 請求額（円・小数 2 桁まで）
  def create_usage(charge_cents:, person: self.person, created_at: now, channel: "mcp")
    UsageRecord.create!(
      person: person,
      channel: channel,
      charge_cents: charge_cents,
      created_at: created_at,
      updated_at: created_at
    )
  end

  describe "#used_cents" do
    it "当日の mcp の charge_cents を合計する" do
      create_usage(charge_cents: "0.15")
      create_usage(charge_cents: "1.85")

      expect(build_limit.used_cents).to eq(BigDecimal("2.00"))
    end

    # charge_cents は decimal(14,2)。0.1 + 0.2 のような浮動小数の誤差を出さない。
    it "小数 2 桁の合計に丸め誤差が出ない" do
      3.times { create_usage(charge_cents: "0.10") }
      create_usage(charge_cents: "0.20")

      expect(build_limit.used_cents).to eq(BigDecimal("0.50"))
      expect(build_limit.used_cents.to_s("F")).to eq("0.5")
    end

    it "web の利用は合計に入らない" do
      create_usage(charge_cents: "500.00", channel: "web")

      expect(build_limit.used_cents).to eq(BigDecimal("0"))
    end

    it "他人の利用は合計に入らない" do
      create_usage(person: other_person, charge_cents: "500.00")

      expect(build_limit.used_cents).to eq(BigDecimal("0"))
    end

    # 2026-02-01 09:00 JST の「当日」= 2026-02-01 00:00 JST 〜 2026-02-02 00:00 JST
    it "JST 0 時をまたぐとリセットされる（前日 23:59 JST は入らない）" do
      create_usage(charge_cents: "500.00", created_at: jst("2026-01-31 23:59:00"))

      expect(build_limit.used_cents).to eq(BigDecimal("0"))
    end

    it "JST 0 時ちょうどの利用は当日に入る" do
      create_usage(charge_cents: "1.00", created_at: jst("2026-02-01 00:00:00"))

      expect(build_limit.used_cents).to eq(BigDecimal("1.00"))
    end

    it "翌日 0 時ちょうどの利用は当日に入らない" do
      create_usage(charge_cents: "1.00", created_at: jst("2026-02-02 00:00:00"))

      expect(build_limit.used_cents).to eq(BigDecimal("0"))
    end
  end

  describe "#exceeded?" do
    before { token.update!(daily_cost_limit_cents: 500) }

    it "上限ちょうどは超過としない" do
      create_usage(charge_cents: "500.00")

      expect(build_limit).not_to be_exceeded
    end

    it "上限を超えたら超過とする" do
      create_usage(charge_cents: "500.01")

      expect(build_limit).to be_exceeded
    end

    it "上限額はトークンが持つ（トークンごとに変わる）" do
      token.update!(daily_cost_limit_cents: 0)
      create_usage(charge_cents: "0.15")

      expect(build_limit.limit_cents).to eq(0)
      expect(build_limit).to be_exceeded
    end

    it "トークンが無い（Cookie 認証）ときは判定しない" do
      create_usage(charge_cents: "10000.00")

      limit = build_limit(token: nil)
      expect(limit.limit_cents).to be_nil
      expect(limit).not_to be_exceeded
    end
  end
end
