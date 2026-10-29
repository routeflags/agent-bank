# frozen_string_literal: true

# トップのカテゴリタイルをデザイン正本（11 列）に揃えるためのシード。
#
# 使い方:
#   bin/rails runner script/seed_categories.rb                 # ローカル
#   docker compose -f compose.production.yaml exec -T web \
#     bundle exec rails runner script/seed_categories.rb       # 本番
#
# デザイン正本のタイルは
#   すべて / 生成AI / データ分析 / 開発・プログラミング / マーケティング /
#   業務自動化 / デザイン / リサーチ / 教育・学習 / 画像生成 / 翻訳
# の 11 個（「すべて」はビュー側の固定タイル）。
#
# 冪等: **日本語名**で同定する（`categories.url` は Category の保存時に
# 名前から自動生成されるため、url をキーにすると重複が作られる）。
CATEGORY_NAMES = [
  ["生成AI", "Generative AI"],
  ["データ分析", "Data analysis"],
  ["開発・プログラミング", "Development"],
  ["マーケティング", "Marketing"],
  ["業務自動化", "Automation"],
  ["デザイン", "Design"],
  ["リサーチ", "Research"],
  ["教育・学習", "Education"],
  ["画像生成", "Image generation"],
  ["翻訳", "Translation"]
].freeze

community = Community.first
abort("community not found") if community.nil?

def find_or_create_root(community, ja, en)
  existing = CategoryTranslation.where(locale: "ja", name: ja)
                                .joins("INNER JOIN categories ON categories.id = category_translations.category_id")
                                .where(categories: { community_id: community.id })
                                .first
  return Category.find(existing.category_id) if existing

  Category.create!(community_id: community.id, parent_id: nil, sort_priority: 0).tap do |category|
    CategoryTranslation.create!(category_id: category.id, locale: "ja", name: ja)
    CategoryTranslation.create!(category_id: category.id, locale: "en", name: en)
  end
end

CATEGORY_NAMES.each_with_index do |(ja, en), index|
  category = find_or_create_root(community, ja, en)
  category.update!(parent_id: nil, sort_priority: index)
  begin
    CategoryTranslation.find_or_initialize_by(category_id: category.id, locale: "ja").update!(name: ja)
  rescue StandardError
    nil
  end
  begin
    CategoryTranslation.find_or_initialize_by(category_id: category.id, locale: "en").update!(name: en)
  rescue StandardError
    nil
  end
  puts "root ##{category.id} #{ja}"
end

# 同名のルートカテゴリが複数ある場合、子・出品を持つものを残して他を削除する。
# 「デフォルトカテゴリ」は対象外（システム用）。
wanted = CATEGORY_NAMES.map(&:first)
wanted.each do |name|
  candidates = Category.where(community_id: community.id, parent_id: nil).select do |category|
    CategoryTranslation.find_by(category_id: category.id, locale: "ja")&.name == name
  end
  next if candidates.size <= 1

  keep = candidates.max_by do |category|
    [Category.where(parent_id: category.id).count + Listing.where(category_id: category.id).count, -category.id]
  end
  (candidates - [keep]).each do |category|
    next if Category.where(parent_id: category.id).exists?
    next if Listing.where(category_id: category.id).exists?

    CategoryTranslation.where(category_id: category.id).delete_all
    category.destroy
    puts "removed duplicate ##{category.id} #{name}"
  end
end

# デザイン正本に無いルートカテゴリで、出品も子も無いものは削除する。
Category.where(community_id: community.id, parent_id: nil).find_each do |category|
  name = CategoryTranslation.find_by(category_id: category.id, locale: "ja")&.name
  next if name.nil?
  next if wanted.include?(name)
  next if Listing.where(category_id: category.id).exists?
  next if Category.where(parent_id: category.id).exists?

  CategoryTranslation.where(category_id: category.id).delete_all
  category.destroy
  puts "removed ##{category.id} #{name}"
end

roots = Category.where(community_id: community.id, parent_id: nil)
puts "done: #{roots.count} root categories"
