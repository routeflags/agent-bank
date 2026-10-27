# frozen_string_literal: true

# 大きな件数の短縮表示（Issue #95）。
#
# 億超えの全桁表示でレイアウトがはみ出すため、1,000 以上は K/M/B で短縮する。
# 正確値は呼び出し側が title 属性に保持する。1,000 未満は現行どおり全桁。
module CompactNumberHelper
  # @param value [Integer, nil] 件数
  # @return [String] 短縮表示（例: '999', '1K', '1.2K', '3.4M', '1.2B'）
  def compact_number(value)
    n = value.to_i
    return number_with_delimiter(n) if n < 1000

    # 丸めで桁上がりする境界（999_999 → '1000K' を避けて '1M' にする）。
    num, unit =
      if n >= 999_500_000
        [n / 1_000_000_000.0, 'B']
      elsif n >= 999_500
        [n / 1_000_000.0, 'M']
      else
        [n / 1000.0, 'K']
      end
    str = num >= 100 ? num.round(0).to_s : format('%.1f', num).sub(/\.0$/, '')
    "#{str}#{unit}"
  end
end
