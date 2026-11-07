# frozen_string_literal: true

# Issue #148: 実行経路（channel）別の利用量を集計する。
#
#   bin/rails 'lamprey:usage_by_channel'     # 直近 30 日
#   bin/rails 'lamprey:usage_by_channel[7]'  # 直近 7 日
#
# `usage_records.channel` は `chat_sessions.channel` を `PersonaExecutorJob`
# が写した値:
#   web — ブラウザのチャット UI（既定）
#   mcp — 外部クライアント（MCP ツール / #144 の実行 API）
#
# 出すのは経路別の COUNT(*) / SUM(total_tokens) / SUM(charge_cents)。
# `charge_cents` は実際に利用者へ請求した額（AI モデルの原価は `cost_cents`）。
# 参照系の集計なので書き込みはしない。
module LampreyUsageByChannel
  DEFAULT_DAYS = 30

  module_function

  # @param value [String, nil] コマンドライン引数
  # @return [Integer] 正の日数（未指定は DEFAULT_DAYS）
  def parse_days(value)
    return DEFAULT_DAYS if value.blank?

    days = Integer(value.to_s, 10)
    return days if days.positive?

    abort "[lamprey:usage_by_channel] days は正の整数で指定してください: #{value}"
  rescue ArgumentError
    abort "[lamprey:usage_by_channel] days が整数ではありません: #{value}（例: 7）"
  end

  # 集計して表示する。
  #
  # @param days [Integer] 直近何日を見るか
  # @param out [IO] 出力先（既定: $stdout）
  # @return [Array<Hash>] 経路別の集計（実行数の多い順）
  def run(days:, out: $stdout)
    since = days.days.ago
    rows = totals(since)

    out.puts "[lamprey:usage_by_channel] 直近 #{days} 日（#{since.to_fs(:db)} 〜 現在）"

    if rows.empty?
      out.puts '  対象 0 件（この期間の利用記録はありません）'
      return rows
    end

    print_rows(rows, out)
    rows
  end

  # 経路別の集計。集計クエリは 3 本（件数・トークン・請求額）に抑える。
  #
  # @param since [Time] 集計開始時刻（含む）
  # @return [Array<Hash>] channel / runs / tokens / charge_cents
  def totals(since)
    scope = UsageRecord.where(created_at: since..)
    counts = scope.group(:channel).count
    tokens = scope.group(:channel).sum(:total_tokens)
    charges = scope.group(:channel).sum(:charge_cents)

    rows = counts.map do |channel, runs|
      {
        channel: channel,
        runs: runs,
        tokens: tokens[channel].to_i,
        charge_cents: charges[channel] || 0
      }
    end
    rows.sort_by { |row| -row[:runs] }
  end

  def print_rows(rows, out)
    rows.each { |row| out.puts detail_line(row) }
    out.puts '  ---'
    out.puts detail_line(summary_row(rows))
  end

  def summary_row(rows)
    {
      channel: '合計',
      runs: rows.sum { |row| row[:runs] },
      tokens: rows.sum { |row| row[:tokens] },
      charge_cents: rows.sum { |row| row[:charge_cents] }
    }
  end

  # 「web : 12 回 / 3,400 トークン / 120.00 円」の 1 行。
  # 桁揃えに format を使わないのは、全角の見出しと半角の値が混在すると
  # 文字数指定では揃わないため。
  def detail_line(row)
    "  #{row[:channel].to_s.ljust(6)}: #{number(row[:runs])} 回 / " \
      "#{number(row[:tokens])} トークン / #{decimal(row[:charge_cents])} 円"
  end

  def number(value)
    ActiveSupport::NumberHelper.number_to_delimited(value)
  end

  def decimal(value)
    Kernel.format('%.2f', value.to_f)
  end
end

namespace :lamprey do
  desc '直近 N 日の利用記録を実行経路（channel）別に集計する（既定 30 日）'
  task :usage_by_channel, %i[days] => :environment do |_task, args|
    LampreyUsageByChannel.run(days: LampreyUsageByChannel.parse_days(args[:days]))
  end
end
