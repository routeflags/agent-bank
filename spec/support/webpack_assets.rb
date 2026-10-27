# frozen_string_literal: true

# webpack ビルド成果物（app/assets/webpack/*.js）が無い環境では、
# ページ描画を伴う request spec はアセット解決で 500 になる。
# `app/assets/webpack` は未追跡の生成物のため、新規 worktree では存在しない。
# 環境差を吸収し、新しい worktree でも同じ結果にするための共通ルール。
module WebpackAssetsHelper
  # 全ページが最低限必要とするバンドル。分割ビルド時は vendor-bundle、
  # レガシー時は webpack_bundles のどちらかが存在すれば描画できる。
  WEBPACK_REQUIRED_BUNDLES = %w[vendor-bundle webpack_bundles].freeze

  def webpack_assets_available?
    WEBPACK_REQUIRED_BUNDLES.any? do |name|
      File.exist?(Rails.root.join("app", "assets", "webpack", "#{name}.js"))
    end
  end
end

RSpec.configure do |config|
  config.include WebpackAssetsHelper
end
