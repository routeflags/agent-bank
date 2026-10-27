# frozen_string_literal: true

# Issue #94: 課金を小数点単位にする。残高・取引・利用料の金額カラムを
# 整数（円）から decimal(14,2)（銭まで保持）に変更する。既存の整数値は
# そのまま小数として読み替えられる（100 → 100.00）。
class DecimalizeBillingMoneyColumns < ActiveRecord::Migration[8.1]
  def up
    change_table :wallets, bulk: true do |t|
      t.change :balance_cents, :decimal, precision: 14, scale: 2, null: false, default: 0
    end
    change_table :credit_transactions, bulk: true do |t|
      t.change :amount_cents, :decimal, precision: 14, scale: 2, null: false
    end
    change_table :usage_records, bulk: true do |t|
      t.change :charge_cents, :decimal, precision: 14, scale: 2, default: 0
      t.change :cost_cents, :decimal, precision: 14, scale: 2, default: 0
    end
  end

  def down
    change_table :wallets, bulk: true do |t|
      t.change :balance_cents, :integer, null: false, default: 0
    end
    change_table :credit_transactions, bulk: true do |t|
      t.change :amount_cents, :integer, null: false
    end
    change_table :usage_records, bulk: true do |t|
      t.change :charge_cents, :integer, default: 0
      t.change :cost_cents, :integer, default: 0
    end
  end
end
