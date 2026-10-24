# frozen_string_literal: true

# カテゴリデータ正規化スクリプト
#
# 背景: db/seeds.rb は複数回実行された際、before_save :uniq_url が翻訳保存前の
# タイミングで URL を上書きするため、同一カテゴリが3系統（generic URL:
# categoryN）重複して作成されていた。また ja 翻訳が英語名のままであった。
#
# このスクリプトは冪等に以下を実施する:
#   1. 正準セット（id 22-45）の日本語名を設定
#   2. 重複セット（id >= 46）を削除（shape リンク・翻訳込み）
#   3. ラク市楽間デザインの6トップカテゴリを作成（slug は homepage の
#      カテゴリカードリンクと一致: generation-ai / data-analysis / development /
#      marketing / automation / design）
#   4. 生成・分析系カテゴリを該当するラクカテゴリ配下へ再親子付け
#
# Run: bundle exec rails runner scripts/normalize_categories.rb

community = Community.find_by!(ident: "agent-bank")
shape = ListingShape.find_by!(community: community, name: "order_type")

JA_NAMES = {
  22 => "デフォルトカテゴリ",
  23 => "テキスト生成",
  24 => "ライティングアシスタント",
  25 => "コードアシスタント",
  26 => "翻訳",
  27 => "要約",
  28 => "チャット・会話",
  29 => "カスタマーサポート",
  30 => "ロールプレイ",
  31 => "画像生成",
  32 => "アート・イラスト",
  33 => "写真編集",
  34 => "動画生成",
  35 => "音声・オーディオ",
  36 => "テキスト読み上げ（TTS）",
  37 => "音声認識（STT）",
  38 => "音楽生成",
  39 => "データ分析",
  40 => "リサーチアシスタント",
  41 => "生産性",
  42 => "メール文面作成",
  43 => "会議メモ",
  44 => "教育・学習",
  45 => "チューティング"
}.freeze

RAKU = [
  { slug: "generation-ai", name: "生成AI" },
  { slug: "data-analysis", name: "データ分析" },
  { slug: "development", name: "開発・プログラミング" },
  { slug: "marketing", name: "マーケティング" },
  { slug: "automation", name: "業務自動化" },
  { slug: "design", name: "デザイン" }
].freeze

REMAP = {
  "generation-ai" => [23, 31, 34, 35],
  "development" => [25],
  "data-analysis" => [39],
  "automation" => [41]
}.freeze

# --- 1. 正準セットの日本語名 ---
JA_NAMES.each do |id, name|
  cat = Category.find_by(id: id)
  next if cat.nil? || cat.community_id != community.id

  t = cat.translations.find_by(locale: "ja") || cat.translations.build(locale: "ja")
  t.name = name
  t.save!
  puts "ja-name: #{id} -> #{name}"
end

# --- 2. 重複セット削除（id >= 46・参照なしを確認済み） ---
dup_ids = Category.where(community_id: community.id).where("id >= ?", 46).pluck(:id)
if dup_ids.any?
  CategoryListingShape.where(category_id: dup_ids).delete_all
  CategoryTranslation.where(category_id: dup_ids).delete_all
  Category.where(id: dup_ids).delete_all
  puts "deleted: #{dup_ids.size} duplicate categories (+ shapes/translations)"
else
  puts "deleted: 0 (already clean)"
end

# --- 3. ラクカテゴリ作成 ---
raku = {}
RAKU.each_with_index do |cfg, i|
  cat = Category.find_or_initialize_by(url: cfg[:slug], community: community)
  if cat.new_record?
    cat.parent_id = nil
    cat.sort_priority = i
    cat.save! # before_save :uniq_url が URL を上書きするため後で直す
  end
  cat.update_column(:url, cfg[:slug])

  t = cat.translations.find_by(locale: "ja") || cat.translations.build(locale: "ja")
  t.name = cfg[:name]
  t.save!

  CategoryListingShape.find_or_create_by!(category: cat, listing_shape: shape)
  raku[cfg[:slug]] = cat
  puts "raku: id=#{cat.id} url=#{cfg[:slug]} name=#{cfg[:name]}"
end

# --- 4. 再親子付け ---
REMAP.each do |slug, ids|
  parent = raku.fetch(slug)
  Category.where(id: ids, community_id: community.id).find_each do |cat|
    next if cat.parent_id == parent.id

    cat.update_column(:parent_id, parent.id)
    puts "reparent: #{cat.id} (#{cat.translations.find_by(locale: 'ja')&.name}) -> #{slug}"
  end
end

total = Category.where(community_id: community.id).count
puts "done. categories=#{total}"
