# frozen_string_literal: true

# GitHub 調達スキルの初期シード（60 件）を登録するため、
# `listings.skill_markdown` を TEXT（64KB 上限）から MEDIUMTEXT（16MB 上限）に拡張する。
#
# 対象 60 件のうち最大の SKILL.md が約 66KB あり、TEXT のままでは
# `import:listings` が MySQL の厳格モードで失敗する（Data too long for column）。
# MEDIUMTEXT への拡張は上限を上げるだけの互換性のある変更で、既存レコードには影響しない。
#
class ChangeSkillMarkdownToMediumtext < ActiveRecord::Migration[8.1]
  def change
    change_column :listings, :skill_markdown, :text, limit: 16_777_215, default: nil, comment: "出品者のスキル説明 (Markdown) — 所有者のみ閲覧可・フロント非表示"
  end
end
