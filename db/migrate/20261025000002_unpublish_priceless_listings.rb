# Issue #52: 全出品は有料。価格未設定（nil/0）の既存出品は
# 削除せず非公開（open=false）にする。データを壊さず公開だけ止める。
# オーナーが価格を入れれば公開に戻せる。
#
# reversible: up で閉じた priceless 出品を down で開き直す。
# ただし up 後に価格が設定された出品は対象外（price_cents 条件で除外される）。
class UnpublishPricelessListings < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE listings
      SET open = false
      WHERE deleted = false
        AND open = true
        AND (price_cents IS NULL OR price_cents = 0)
    SQL
  end

  def down
    execute(<<~SQL.squish)
      UPDATE listings
      SET open = true
      WHERE deleted = false
        AND open = false
        AND (price_cents IS NULL OR price_cents = 0)
    SQL
  end
end
