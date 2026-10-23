# frozen_string_literal: true

# 出品フォームでスキルを入力・保存できるようにする（Issue #13）
#
# 所有者のみ閲覧・編集できる非公開の Markdown テキスト。
# フロント（詳細ページ・一覧・検索結果）や検索インデックス、
# AI チャットのシステムプロンプトには一切混入させない。
#
class AddSkillMarkdownToListings < ActiveRecord::Migration[8.1]
  def change
    add_column :listings, :skill_markdown, :text, default: nil, comment: "出品者のスキル説明 (Markdown) — 所有者のみ閲覧可・フロント非表示"
  end
end
