# frozen_string_literal: true

# Issue #59（新仕様）: 出品者手数料率は使わないため列を撤去する。
# 既存行の値は参照されないまま残っているだけなので、データ移行は行わない。
class RemoveSellerCommissionRateFromListings < ActiveRecord::Migration[8.1]
  def change
    remove_column :listings, :seller_commission_rate, :integer
  end
end
