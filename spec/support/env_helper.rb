# frozen_string_literal: true

# ENV を一時的に差し替えるテスト用ヘルパー（Issue #120）
module EnvHelper
  # 指定したキーだけをブロック内で差し替え、抜けたら元の値に戻す。
  # 値に nil を渡すと「未設定」にする。
  def with_env(values)
    keys = values.keys
    saved = keys.index_with { |key| ENV[key] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # 管理画面保護の ENV を未設定にした上で、指定分だけ設定する。
  def with_admin_env(values = {}, &block)
    with_env({ "ADMIN_ALLOWED_IPS" => nil }.merge(values), &block)
  end
end

RSpec.configure do |config|
  config.include EnvHelper
end
