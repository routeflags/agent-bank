# frozen_string_literal: true

# ルートコンストラクタ: 予約語を username パラメータから除外
# config/routes.rb で person ルートのconstraints として使用
#
# 例:
#   resources :people, param: :username, path: "", only: :show,
#     constraints: UsernameConstraint.new
#
class UsernameConstraint
  RESERVED = YAML.load_file(Rails.root.join("config", "username_blacklist.yml")).freeze

  def matches?(request)
    path = request.fullpath
    # /fi/admin2 → username = "admin2"
    # /en/tailangtian → username = "tailangtian"
    # /fi/listings/20 → username = nil (path が long)
    parts = path.split("/").reject(&:blank?)

    # locale の後に username が来るのが person ルート
    # /:locale/:username の形式で、username のみ（追加パスがない）
    return true unless parts.length == 2

    username = parts.last
    return true if username.blank?

    !RESERVED.include?(username.downcase)
  end
end
