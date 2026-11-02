# frozen_string_literal: true

# TLS（HTTPS）強制の判定（Issue #120 / #121）
#
# 本番は現在 HTTP 運用のため、暗黙には有効化しない。
# `FORCE_SSL=1` か、`APP_DOMAIN` に `https://` を含む URL が設定されているときだけ
# `config.force_ssl` とセッション Cookie の `secure` フラグを有効にする。
#
# 注意: Caddy が HTTP のままだと https へリダイレクトして到達不能になる。
# 有効化は Caddyfile の TLS 切替（#121）と同時に行うこと。
# 手順は documents/guides/security_hardening.md を参照。
module TlsSettings
  TRUE_VALUES = %w[1 true yes on].freeze

  module_function

  # @return [Boolean] TLS を強制するか
  def force_ssl?
    force_ssl_env? || https_app_domain?
  end

  def force_ssl_env?
    TRUE_VALUES.include?(ENV["FORCE_SSL"].to_s.strip.downcase)
  end

  def https_app_domain?
    ENV["APP_DOMAIN"].to_s.strip.downcase.start_with?("https://")
  end
end
