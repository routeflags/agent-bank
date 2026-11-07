# frozen_string_literal: true

# MCP 実行の日次利用上限（Issue #147）。
#
# 上限額はリクエストに使われたトークン（`api_tokens.daily_cost_limit_cents`）
# が持つ。判定に使う「使った額」は**人単位**の合計で、対象は当日の
# `channel = "mcp"` の `charge_cents`（利用者への請求額）。同じ人が複数の
# トークンを持っていても、その人の MCP 利用はすべて同じ合計に入る。
#
# 日界は JST 0 時。日本市場向けのプロダクトなので、UTC の日付ではなく
# 利用者の体感に合わせる。
#
# 合計は `usage_records` の decimal(14,2) を SQL の SUM で合算するため、
# アプリ側で浮動小数に変換してから足すことはしない（丸め誤差を出さない）。
#
# 上限ちょうどは通す：`used_cents > limit_cents` のときだけ超過とする。
# 実行前には「これから使う額」が決まらないため、上限に達した時点で止めると
# 最後の 1 回が使えなくなる。超えた次のリクエストから止める。
#
# token が nil（Cookie 認証）のときは上限額が決まらないので判定しない。
class McpDailyLimit
  # 集計対象の経路。
  CHANNEL = ChatSession::CHANNEL_MCP
  # 日界のタイムゾーン。
  TIME_ZONE = "Asia/Tokyo"

  attr_reader :person, :token

  # @param person [Person] 利用者
  # @param token [APIToken, nil] このリクエストの認証に使ったトークン
  # @param now [Time] 判定基準時刻（spec で日界を固めるために差し替える）
  def initialize(person:, token:, now: Time.current)
    @person = person
    @token = token
    @now = now
  end

  # 日次上限額（円）。トークンが無ければ nil。
  #
  # @return [Integer, nil]
  def limit_cents
    token&.daily_cost_limit_cents
  end

  # 当日（JST）の MCP 利用の請求額合計（円）。
  #
  # 超過判定とレスポンスの両方で使うので一度だけ引く。
  #
  # @return [BigDecimal] 小数 2 桁（利用記録が無ければ 0）
  def used_cents
    @used_cents ||= UsageRecord
                    .where(person_id: person.id, channel: CHANNEL, created_at: day_range)
                    .sum(:charge_cents)
                    .to_d
  end

  # 上限を超えているか。
  #
  # @return [Boolean]
  def exceeded?
    limit = limit_cents
    return false if limit.nil?

    used_cents > limit
  end

  # 当日の範囲（JST 0 時以上、翌日 0 時未満）。
  #
  # @return [Range<Time>]
  def day_range
    day_start = @now.in_time_zone(TIME_ZONE).beginning_of_day
    day_start...(day_start + 1.day)
  end
end
