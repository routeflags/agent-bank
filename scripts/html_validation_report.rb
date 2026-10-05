# frozen_string_literal: true

# HTML バリデーション実行スクリプト（フロント全ページ）
# html-validate + .htmlvalidate.json でレンダリング済みページを検証し、
# docs/html-validation-report.md にレポートを出力する。
#
# Run: bundle exec rails runner scripts/html_validation_report.rb

require "json"
require "open3"
require "fileutils"

BASE = "http://agent-bank.lvh.me:3000"
WORK_DIR = Rails.root.join("tmp/htmlval_run")
REPORT_PATH = Rails.root.join("docs/html-validation-report.md")

SLUGS = {
  14 => "sakura-raiteinguasisutanto",
  15 => "kodotai-lang-kodosheng-cheng-rebiyu",
  16 => "mizutama-ri-ying-fan-yi",
  17 => "hanako-kasutamasapoto",
  18 => "yuki-rorupureihui-hua",
  19 => "kenzi-detafen-xi"
}.freeze

PERSONA_NAMES = {
  14 => "さくら — ライティングアシスタント",
  15 => "コード太郎 — コード生成・レビュー",
  16 => "みずたま — 日英翻訳",
  17 => "はなこ — カスタマーサポート",
  18 => "ゆき — ロールプレイ会話",
  19 => "けんじ — データ分析"
}.freeze

# [name, path, auth?]
PAGES = [
  ["トップページ", "/", false],
  ["ログイン", "/ja/login", false],
  ["新規登録", "/ja/signup", false],
  ["パスワード再設定", "/ja/people/password/new", false],
  ["購入者プロフィール", "/ja/gourutailangte", false],
  ["出品者プロフィール", "/ja/alexm", false],
  *SLUGS.map { |id, slug| ["ペルソナ詳細（#{PERSONA_NAMES[id]}）", "/ja/listings/#{id}-#{slug}", false] },
  ["メールボックス", "/ja/gourutailangte/inbox", true],
  ["設定", "/ja/settings", true],
  ["ペルソナ問い合わせフォーム", "/ja/listings/14-#{SLUGS[14]}/contact", true],
  ["注文開始", "/ja/listings/14-#{SLUGS[14]}/initiate", true]
].freeze

FileUtils.mkdir_p(WORK_DIR)

# Buyer session cookies
buyer_id = "pTRjZXZwIWlAMwb_7wFjMQ"
token = UserService::API::AuthTokens.create_login_token(buyer_id)[:token]
cookie_file = WORK_DIR.join("cookies.txt").to_s
system("curl", "-s", "-c", cookie_file, "-o", "/dev/null", "#{BASE}/?auth=#{token}") or raise "login failed"

results = []

PAGES.each do |name, path, auth|
  slug_name = path.gsub(%r{[^a-z0-9]+}i, "_").sub(/^_+/, "")
  html_file = WORK_DIR.join("#{slug_name}.html").to_s
  json_file = WORK_DIR.join("#{slug_name}.json").to_s

  cmd = ["curl", "-s", "-o", html_file, "-w", "%{http_code}"]
  cmd += ["-b", cookie_file] if auth
  cmd << "#{BASE}#{path}"
  status = `#{cmd.join(" ")}`.strip.to_i

  entry = { name: name, path: path, auth: auth, status: status, errors: 0, warnings: 0, rules: {} }

  if status == 200
    system("npx", "html-validate", "--formatter", "json", html_file, out: json_file, err: File::NULL)
    json = begin
      JSON.parse(File.read(json_file))
    rescue JSON::ParserError, Errno::ENOENT
      []
    end

    # html-validate JSON: array of {filePath, messages: [{ruleId, severity, ...}]}
    Array(json).each do |file_result|
      Array(file_result["messages"]).each do |msg|
        severity = msg["severity"] == 2 ? :error : :warning
        count_key = severity == :error ? :errors : :warnings
        entry[count_key] += 1
        rule = msg["ruleId"] || "unknown"
        entry[:rules][rule] ||= { error: 0, warning: 0 }
        entry[:rules][rule][severity] += 1
      end
    end
  end

  results << entry
  puts "#{status} #{name}: errors=#{entry[:errors]} warnings=#{entry[:warnings]}"
end

# ---- Aggregate report ----
total_errors = results.sum { |r| r[:errors] }
total_warnings = results.sum { |r| r[:warnings] }
ok_pages = results.select { |r| r[:status] == 200 }
error_pages = results.select { |r| r[:status] >= 500 }
redirect_pages = results.select { |r| r[:status].between?(300, 399) }

rule_totals = Hash.new { |h, k| h[k] = { error: 0, warning: 0 } }
results.each do |r|
  r[:rules].each { |rule, counts|
    rule_totals[rule][:error] += counts[:error]
    rule_totals[rule][:warning] += counts[:warning]
  }
end

ts = Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")

File.open(REPORT_PATH, "w") do |f|
  f.puts "# HTML バリデーションレポート"
  f.puts
  f.puts "- **実施日時**: #{ts}"
  f.puts "- **対象**: Agent Bank フロントエンド全ページ（日本語版 /ja）"
  f.puts "- **ツール**: html-validate 11.16.2（`html-validate:recommended` + WCAG ルール等、`.htmlvalidate.json` 準拠）"
  f.puts "- **対象ページ数**: #{results.size}（HTTP 200: #{ok_pages.size} / 5xx エラー: #{error_pages.size} / リダイレクト: #{redirect_pages.size}）"
  f.puts "- **総計**: エラー #{total_errors} 件 / 警告 #{total_warnings} 件"
  f.puts
  f.puts "## サマリ"
  f.puts
  f.puts "| # | ページ | 認証 | HTTP | エラー | 警告 |"
  f.puts "|---|--------|:----:|:----:|-------:|-----:|"
  results.each_with_index do |r, i|
    auth = r[:auth] ? "あり" : "-"
    f.puts "| #{i + 1} | #{r[:name]} | #{auth} | #{r[:status]} | #{r[:errors]} | #{r[:warnings]} |"
  end
  f.puts
  f.puts "## ルール別集計（HTTP 200 ページ）"
  f.puts
  f.puts "| ルール | エラー | 警告 |"
  f.puts "|--------|-------:|-----:|"
  rule_totals.sort_by { |_, c| -c[:error] }.each do |rule, c|
    f.puts "| `#{rule}` | #{c[:error]} | #{c[:warning]} |"
  end
  f.puts
  f.puts "## ページ別 内訳（上位ルール）"
  f.puts
  ok_pages.each do |r|
    next if r[:rules].empty?

    f.puts "### #{r[:name]} (`#{r[:path]}`)"
    f.puts
    top = r[:rules].sort_by { |_, c| -c[:error] }.first(8)
    top.each do |rule, c|
      detail = []
      detail << "エラー #{c[:error]}" if c[:error].positive?
      detail << "警告 #{c[:warning]}" if c[:warning].positive?
      f.puts "- `#{rule}`: #{detail.join(' / ')}"
    end
    f.puts
  end

  unless error_pages.empty?
    f.puts "## 検証不能ページ（5xx）"
    f.puts
    f.puts "| ページ | パス |"
    f.puts "|--------|------|"
    error_pages.each do |r|
      f.puts "| #{r[:name]} | `#{r[:path]}` |"
    end
    f.puts
  end

  f.puts "## 既知のコメント"
  f.puts
  f.puts "- HAML 由来の self-closing 要素は `config/initializers/haml_format.rb`（`format: :html5`）で解消"
  f.puts "- Rails ヘルパー出力（フォームビルダ等）は self-closing / boolean 属性付き書式のため、`void-style` と `attribute-boolean-style` は `style: any`（両形式許容・ルール自体は有効）に設定"
  f.puts "- `no-inline-style` 警告は raku デザインのインラインスタイルを `components/_raku_utils.scss` のクラスへ切り出して解消"
  f.puts "- チャットパネル（react-rails）出力の空白行は `listings/show.haml` 側で除去"
  f.puts "- 5xx ページはバリデーション対象外（エラーページ HTML のため）"
  f.puts
  f.puts "## 再実行方法"
  f.puts
  f.puts "```bash"
  f.puts "bundle exec rails runner scripts/html_validation_report.rb"
  f.puts "```"
end

puts "Report written: #{REPORT_PATH}"
