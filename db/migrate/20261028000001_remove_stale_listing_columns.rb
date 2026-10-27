# frozen_string_literal: true

# Issue #114: 開発 DB に残っていた撤去済みカラムを収束させる。
#
# listings.short_description / external_apis（Issue #55, #56 で撤去）、
# seller_commission_rate（Issue #59 で撤去）、version_number / publisher_name
# （Issue #60 で撤去）は、対応するマイグレーションが適用済みのはずだが、
# ダンプ復元等で古い列が残った開発 DB が存在した（db/structure.sql には無い）。
# 適用済み DB では何もしない（column_exists? ガードで冪等）。
class RemoveStaleListingColumns < ActiveRecord::Migration[8.1]
  def up
    remove_column :listings, :short_description, :text if column_exists?(:listings, :short_description)
    remove_column :listings, :external_apis, :json if column_exists?(:listings, :external_apis)
    remove_column :listings, :version_number, :string if column_exists?(:listings, :version_number)
    remove_column :listings, :publisher_name, :string if column_exists?(:listings, :publisher_name)
    remove_column :listings, :seller_commission_rate, :integer if column_exists?(:listings, :seller_commission_rate)
  end

  def down
    # 撤去済みのデッドカラムのため復元しない。
  end
end
