# frozen_string_literal: true

require "ipaddr"

# /admin 配下のアクセス制限（Issue #120）
#
# `ADMIN_ALLOWED_IPS` が設定されているときだけ、送信元 IP の許可リストを強制する。
# 未設定（空文字を含む）なら何もしないため、開発・テスト環境の挙動は従来どおり。
#
# - ADMIN_ALLOWED_IPS: カンマ区切りの IP / CIDR
#   例: "203.0.113.10,198.51.100.0/24,::1"（IPv6 も指定できる）
#
# 設定が壊れている（解釈できる値が一つも無い）場合は「全拒否」に倒す。
# 設定ミスで保護が無効になるより、403 で気付ける方が安全なため。
class AdminAccessControl
  ALLOWED_IPS_KEY = "ADMIN_ALLOWED_IPS"

  class << self
    # 許可レンジ。nil（＝未設定）なら IP 制限を行わない。
    # 設定されているが一つも解釈できない場合は空配列（＝全拒否）。
    #
    # @return [Array<IPAddr>, nil]
    def allowed_ip_ranges(raw = ENV[ALLOWED_IPS_KEY])
      value = raw.to_s.strip
      return nil if value.empty?

      ranges = value.split(",").filter_map { |entry| parse_ip(entry) }

      if ranges.empty?
        Rails.logger.warn(
          "[AdminAccessControl] #{ALLOWED_IPS_KEY} を解釈できませんでした。" \
          "/admin はすべての IP を拒否します（設定値を確認してください）"
        )
      end

      ranges
    end

    def ip_restriction_enabled?(raw = ENV[ALLOWED_IPS_KEY])
      !allowed_ip_ranges(raw).nil?
    end

    # @param remote_ip [String, nil] request.remote_ip
    def ip_allowed?(remote_ip, raw = ENV[ALLOWED_IPS_KEY])
      ranges = allowed_ip_ranges(raw)
      return true if ranges.nil?

      addr = parse_ip(remote_ip)
      return false if addr.nil?

      ranges.any? { |range| range.include?(addr) }
    end

    private

    def parse_ip(value)
      addr = value.to_s.strip
      return nil if addr.empty?

      ip = IPAddr.new(addr)
      # ::ffff:127.0.0.1 のような IPv4 射影 IPv6 は IPv4 として扱う
      ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped? ? ip.native : ip
    rescue IPAddr::Error
      nil
    end
  end
end
