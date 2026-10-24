# frozen_string_literal: true

# Issue #20: カスタムフィールドに「長文（Markdown）入力」を持たせる。
#
# 既存の TextField は 1 行の text_field で描画されるため、スキル説明のような
# Markdown を書く欄には向かない。long_text を true にしたテキストフィールドだけを
# textarea で描画し、詳細ページの機能タブでは Markdown としてレンダリングする。
class AddLongTextToCustomFields < ActiveRecord::Migration[8.1]
  def change
    # コメントは DB に残すが、rubocop の整形都合上ここでは付けない（コード内に記録）
    add_column :custom_fields, :long_text, :boolean, default: false, null: false
  end
end
