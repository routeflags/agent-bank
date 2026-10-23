# frozen_string_literal: true

# Issue #20: 機能タブ用のカスタムフィールド（スキル）を用意する。
#
# 管理画面（/ja/admin/listings/listing_fields）で手作業してもよいが、
# 開発・ステージング・本番で同じ状態を再現できるようタスクにする。
# 何度実行しても同じ結果になる（冪等）。
#
#   bin/rails 'lamprey:custom_fields:skill'
#   COMMUNITY_ID=6 bin/rails 'lamprey:custom_fields:skill'
namespace :lamprey do
  namespace :custom_fields do
    desc "スキル（Markdown）カスタムフィールドを作成し、主要カテゴリに紐付ける"
    task skill: :environment do
      community = if ENV["COMMUNITY_ID"].present?
                    Community.find(ENV["COMMUNITY_ID"])
                  else
                    Community.first
                  end
      abort "コミュニティが見つかりません" unless community

      category_urls = %w[generation-ai data-analysis development]
      roots = Category.where(url: category_urls)
      abort "対象カテゴリが見つかりません: #{category_urls.join(', ')}" if roots.empty?

      # 出品はサブカテゴリに紐づくことが多いため、主要カテゴリだけでなく
      # その子孫カテゴリにも紐付ける（リストのフォームは listing の
      # category に紐づくフィールドだけを表示するため）。
      collect = ->(category) { [category] + category.children.flat_map { |child| collect.call(child) } }
      categories = roots.flat_map { |root| collect.call(root) }

      field = TextField.where(community_id: community.id)
                       .find { |f| f.names.any? { |n| n.value == "スキル" } }
      action = field ? "更新" : "作成"
      field ||= TextField.new(community: community)

      field.entity_type = :for_listing
      field.long_text = true # 複数行（Markdown）入力
      field.required = false
      field.search_filter = false # 一覧の検索フィルタには出さない
      field.sort_priority ||= community.custom_fields.maximum(:sort_priority).to_i + 1
      field.name_attributes = { "ja" => "スキル", "en" => "Skills" }
      field.category_attributes = categories.map { |c| { category_id: c.id } }
      field.save!

      puts "#{action}しました: custom_field_id=#{field.id} " \
           "categories=#{categories.map(&:url).join(',')} long_text=#{field.long_text?}"
    end
  end
end
