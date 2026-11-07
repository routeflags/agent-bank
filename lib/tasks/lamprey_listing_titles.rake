# frozen_string_literal: true

# Issue #137: 出品タイトルの正規化。
#
# シードや初期データのタイトルが「ペルソナ名 — 機能」形式になっており、
# カード・ページタイトルとして冗長。**「—」（U+2014）より前を落として
# 機能名だけ**にする。既存の手動出品も同じ書式なので一律で対象にする。
#
# 既定はドライラン（対象の出力のみ）で、適用は `COMMIT=1`
# （`lamprey:normalize_listing_ratings` と同じ流儀）。
#
#   bin/rails "lamprey:normalize_listing_titles"            # ドライラン
#   COMMIT=1 bin/rails "lamprey:normalize_listing_titles"   # 適用
#
# slug は変えない（既存リンクを壊さないため）。`update_columns` を使い、
# `updated_at` は動かさない（並び順・キャッシュに影響させない）。
module LampreyListingTitles
  DASH = "—"

  module_function

  # @return [Array<Hash>] 正規化対象（id / before / after）
  def normalization_targets
    Listing.unscoped.where("title LIKE ?", "%#{DASH}%").order(:id).filter_map do |listing|
      normalized = normalize(listing.title)
      next if normalized.blank? || normalized == listing.title

      { listing: listing, before: listing.title, after: normalized }
    end
  end

  # 「ペルソナ名 — 機能」から「機能」を取り出す。区切りが無ければそのまま。
  def normalize(title)
    title.to_s.split(DASH, 2)[1].to_s.strip.presence || title.to_s.strip
  end

  # @param apply [Boolean] true なら実際に書き換える（COMMIT=1）
  def run(apply:)
    puts "[lamprey:normalize_listing_titles] mode=#{apply ? 'commit' : 'dry-run'}"

    targets = normalization_targets
    if targets.empty?
      puts "対象 0 件（すべて正規化済み）"
      return
    end

    targets.each { |t| puts "  ##{t[:listing].id} #{t[:before]} -> #{t[:after]}" }
    puts "対象 #{targets.size} 件"

    if apply
      targets.each { |t| t[:listing].update_columns(title: t[:after]) }
      puts "適用しました: #{targets.size} 件"
    else
      puts "ドライラン: DB は変更していません。適用するには COMMIT=1 を付けて再実行してください。"
    end
  end
end

namespace :lamprey do
  desc "出品タイトルから「ペルソナ名 — 」の前置きを外す（COMMIT=1 で適用）"
  task normalize_listing_titles: :environment do
    LampreyListingTitles.run(apply: ENV["COMMIT"].to_s == "1")
  end
end
