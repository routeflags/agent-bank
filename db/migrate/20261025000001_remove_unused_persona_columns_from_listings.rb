# frozen_string_literal: true

# 未使用のペルソナ関連列を撤去する（Issue #55, #56）。
#
# - listings.external_apis: 書き込み口がなく全出品で空。参照は
#   ChatSession#system_prompt と Listing#persona_card のみだった。
# - listings.short_description: 入力欄・画面表示・AI 参照のいずれもなく、
#   参照は Listing#persona_card のみだった。
# - 同じ Capafy 移行で入った version_number / publisher_name には触れない。
class RemoveUnusedPersonaColumnsFromListings < ActiveRecord::Migration[8.1]
  def change
    change_table :listings, bulk: true do |t|
      t.remove :external_apis, type: :json
      t.remove :short_description, type: :text
    end
  end
end