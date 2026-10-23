# frozen_string_literal: true

# Sprockets で application.css（SCSS 全体）をコンパイルし、指定パスへ書き出す。
#
# 用途: テーマ配色の静的検証。コンパイル後に
#   node scripts/theme_contrast_check.js --css <出力パス>
# でコントラスト比を実測する（稼働サーバー不要）。
#
# Usage:
#   bundle exec rails runner scripts/compile_application_css.rb /tmp/application.css

output_path = ARGV[0]
abort("usage: bundle exec rails runner scripts/compile_application_css.rb <output.css>") if output_path.nil? || output_path.empty?

assets = Rails.application.assets || abort("Sprockets environment is not available (development で実行してください)")
asset = assets["application.css"] || abort("application.css が見つかりません")

File.write(output_path, asset.to_s)
puts "compiled application.css -> #{output_path} (#{File.size(output_path)} bytes)"
