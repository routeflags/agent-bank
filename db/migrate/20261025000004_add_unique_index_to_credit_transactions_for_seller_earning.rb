# frozen_string_literal: true

# Issue #59: 出品者への収益付与（seller_earning）の冪等性をDB制約で担保する。
# MySQL の UNIQUE は NULL を複数許容するため、reference が NULL の既存行
# （topup / usage_deduction 等）には影響しない。
class AddUniqueIndexToCreditTransactionsForSellerEarning < ActiveRecord::Migration[8.1]
  def change
    add_index :credit_transactions,
              [:transaction_type, :reference_type, :reference_id],
              unique: true,
              name: "index_credit_transactions_on_type_and_reference_unique"
  end
end
