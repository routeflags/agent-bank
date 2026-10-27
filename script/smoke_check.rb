# frozen_string_literal: true

# 主要画面のスモーク E2E スクリプト（Issue #118）。
#
# Rails に依存しない単体 Ruby（標準ライブラリのみ）で、外部のベース URL に
# HTTP でアクセスして主要画面の回帰を検出する。
#
# 使い方:
#   ruby script/smoke_check.rb http://localhost:3000
#
# 対象（ja ロケール・未ログインで 200 を期待）:
#   - /ja/                                                 トップ
#   - /ja/browse                                          一覧
#   - /ja/docs                                            ドキュメント
#   - /ja/listings/15-kodotai-lang-kodosheng-cheng-rebiyu 詳細（存在しなければ 404 を許容せず失敗）
#   - /ja/gourutailangte                                  ユーザープロフィール
#
# 対象外（認証が必要な画面）:
#   - /ja/settings、/:username 配下の設定・受信箱、/ja/listings/new 等は
#     未ログインで 302（`/` へのリダイレクト）を期待するため 200 チェックの対象外。
#     本スクリプトでは代表として /ja/settings が 302 を返すことだけを確認する。
#
# 確認項目:
#   - 各ページが HTTP 200 を返すこと
#   - 主要セレクタの存在（トップ: raku-search-box / product-link /
#     raku-stats__item / site-footer、一覧: cards（トップと同じカード）、
#     詳細: raku-price-box、ドキュメント: raku-page / raku-docs-section、
#     プロフィール: raku-profile）
#   - 禁止文言が出ていないこと
#   - トップが参照する CSS から raku_hero の digested URL を抽出し 200 で返ること
#
# 終了コード: 成功時 0、失敗時 1。結果は 1 行 1 項目で OK / NG を出す。
# 実行時間は 15 秒以内を目安にする（各リクエストに open/read タイムアウト 5 秒）。

require "net/http"
require "uri"

TIMEOUT_SEC = 5
LISTING_PATH = "/ja/listings/15-kodotai-lang-kodosheng-cheng-rebiyu"
PROFILE_PATH = "/ja/gourutailangte"
FORBIDDEN_LABEL = "※デモ数値/※サンプル/高評価/★"

def forbidden_words
  ["※デモ数値", "※サンプル", "高評価", "★"]
end

def fetch(base, path_or_url)
  url = path_or_url.start_with?("http") ? path_or_url : "#{base}#{path_or_url}"
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = TIMEOUT_SEC
  http.read_timeout = TIMEOUT_SEC
  http.use_ssl = (uri.scheme == "https")
  req = Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => "lamprey-smoke-check" })
  res = http.request(req)
  body = res.body.to_s.dup.force_encoding("UTF-8")
  body = body.scrub
  [res.code.to_i, body, res["location"].to_s]
rescue StandardError
  [-1, "", ""]
end

base_arg = ARGV[0]
if base_arg.nil? || base_arg.empty?
  puts "NG 使い方: ruby script/smoke_check.rb http://localhost:3000"
  exit 1
end

base = base_arg.sub(%r{/+$}, "")
begin
  base_uri = URI.parse(base)
  unless base_uri.is_a?(URI::HTTP)
    puts "NG ベース URL が不正です: #{base_arg}"
    exit 1
  end
rescue URI::InvalidURIError
  puts "NG ベース URL が不正です: #{base_arg}"
  exit 1
end

results = []
reporter = lambda do |ok, message|
  results << ok
  puts "#{ok ? 'OK' : 'NG'} #{message}"
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# --- トップ ---
code, top_body, _loc = fetch(base, "/ja/")
reporter.call(code == 200, "GET /ja/ が 200 を返した（実際: #{code}）")
if code == 200
  reporter.call(top_body.include?("raku-search-box"), "トップに raku-search-box が存在する")
  reporter.call(top_body.include?("product-link"), "トップに product-link が存在する")
  reporter.call(top_body.include?("raku-stats__item"), "トップに raku-stats__item が存在する")
  reporter.call(top_body.include?("site-footer"), "トップに site-footer が存在する")
  hit = forbidden_words.find { |w| top_body.include?(w) }
  reporter.call(hit.nil?, hit.nil? ? "トップに禁止文言（#{FORBIDDEN_LABEL}）が出ていない" : "トップに禁止文言が出ていない（検出: #{hit}）")
else
  reporter.call(false, "トップのセレクタ確認をスキップ（トップが 200 以外）")
end

# --- 一覧 ---
code, browse_body, _loc = fetch(base, "/ja/browse")
reporter.call(code == 200, "GET /ja/browse が 200 を返した（実際: #{code}）")
if code == 200
  reporter.call(browse_body.include?("product-link"), "一覧にカード要素（product-link）が存在する")
  hit = forbidden_words.find { |w| browse_body.include?(w) }
  reporter.call(hit.nil?, hit.nil? ? "一覧に禁止文言（#{FORBIDDEN_LABEL}）が出ていない" : "一覧に禁止文言が出ていない（検出: #{hit}）")
end

# --- ドキュメント ---
code, docs_body, _loc = fetch(base, "/ja/docs")
reporter.call(code == 200, "GET /ja/docs が 200 を返した（実際: #{code}）")
if code == 200
  reporter.call(docs_body.include?("raku-page"), "ドキュメントに raku-page が存在する")
  reporter.call(docs_body.include?("raku-docs-section"), "ドキュメントに raku-docs-section が存在する")
  hit = forbidden_words.find { |w| docs_body.include?(w) }
  reporter.call(hit.nil?, hit.nil? ? "ドキュメントに禁止文言（#{FORBIDDEN_LABEL}）が出ていない" : "ドキュメントに禁止文言が出ていない（検出: #{hit}）")
end

# --- 詳細（存在しなければ 404 を許容せず失敗） ---
code, listing_body, _loc = fetch(base, LISTING_PATH)
reporter.call(code == 200, "GET #{LISTING_PATH} が 200 を返した（実際: #{code}、404 は許容しない）")
if code == 200
  reporter.call(listing_body.include?("raku-price-box"), "詳細に raku-price-box が存在する")
  hit = forbidden_words.find { |w| listing_body.include?(w) }
  reporter.call(hit.nil?, hit.nil? ? "詳細に禁止文言（#{FORBIDDEN_LABEL}）が出ていない" : "詳細に禁止文言が出ていない（検出: #{hit}）")
end

# --- プロフィール ---
code, profile_body, _loc = fetch(base, PROFILE_PATH)
reporter.call(code == 200, "GET #{PROFILE_PATH} が 200 を返した（実際: #{code}）")
if code == 200
  reporter.call(profile_body.include?("raku-profile"), "プロフィールに raku-profile が存在する")
  hit = forbidden_words.find { |w| profile_body.include?(w) }
  reporter.call(hit.nil?, hit.nil? ? "プロフィールに禁止文言（#{FORBIDDEN_LABEL}）が出ていない" : "プロフィールに禁止文言が出ていない（検出: #{hit}）")
end

# --- ヒーロー画像（digested URL が 200） ---
# トップ HTML 直下ではなく、トップが参照する application-*.css 内に
# /assets/rakuichi/raku_hero-<digest>.png として埋め込まれている。
check_hero_image(base, top_body, reporter)

# --- 対象外（認証必須）の期待ステータス確認 ---
# /ja/settings 等は未ログインで 200 にならない。`/` への 302 を期待する。
code, _body, location = fetch(base, "/ja/settings")
reporter.call(code == 302, "GET /ja/settings が 302 を返した（実際: #{code}、認証必須のため対象外・200 を期待しない、Location: #{location}）")

# ヒーロー画像の digested URL を CSS から抽出し、200 を返すか確認する。
# 入れ子が深くなるためメソッドに切り出す（Metrics/BlockNesting 対策）。
def check_hero_image(base, top_body, reporter)
  if top_body.nil? || top_body.empty?
    reporter.call(false, "ヒーロー画像の確認をスキップ（トップ取得失敗）")
    return
  end

  css_path = top_body[%r{/assets/application-[^"']+\.css}]
  if css_path.nil?
    reporter.call(false, "ヒーロー画像の CSS（application-*.css）がトップから抽出できなかった")
    return
  end

  css_code, css_body, _loc = fetch(base, css_path)
  if css_code != 200
    reporter.call(false, "ヒーロー画像元の CSS #{css_path} が 200 を返した（実際: #{css_code}）")
    return
  end

  hero_url = css_body[%r{/assets/rakuichi/raku_hero-[^"')\s]+\.png}]
  if hero_url.nil?
    reporter.call(false, "ヒーロー画像（raku_hero の digested URL）が CSS から抽出できなかった")
    return
  end

  img_code, _img_body, _loc = fetch(base, hero_url)
  reporter.call(img_code == 200, "ヒーロー画像 #{hero_url} が 200 を返した（実際: #{img_code}）")
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
failed = results.count(false)
if failed.zero?
  puts "OK 全 #{results.size} 項目が成功（#{format('%.1f', elapsed)}秒）"
  exit 0
else
  puts "NG #{failed}/#{results.size} 項目が失敗（#{format('%.1f', elapsed)}秒）"
  exit 1
end
