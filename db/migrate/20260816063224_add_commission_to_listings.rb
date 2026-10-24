# frozen_string_literal: true

# 双方向コミッション体系の実装
#
# Model A (AI Direct): トークン原価 × (1 + プラットフォームコミッション%)
# Model B (Seller Persona): 出品ペルソナ価格 × (1 + 出品者コミッション% + プラットフォームコミッション%)
#
class AddCommissionToListings < ActiveRecord::Migration[8.1]
  def change
    # === listings テーブル ===
    # 出品者コミッション率（出品者自身が設定、%）
    # Model B のみ使用。Model A では NULL
    add_column :listings, :seller_commission_rate, :integer, default: nil, comment: "出品者コミッション率 (%) — 出品ペルソナ価格に追加"

    # === payment_settings テーブル ===
    # プラットフォームコミッション率（管理者が設定、%）
    # Model A でも Model B でも使用
    unless column_exists?(:payment_settings, :platform_commission_rate)
      add_column :payment_settings, :platform_commission_rate, :integer, default: 0, comment: "プラットフォームコミッション率 (%)"
    end
  end
end
