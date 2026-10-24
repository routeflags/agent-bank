# frozen_string_literal: true

require 'rails_helper'

# 出品フォーム価格表示の回帰 spec（Issue #30）。
#
# - 円マークが入力欄の前（左側）に描画される
# - 単一単位の場合の単位表示が「円 / 100万トークン」固定である
# - listing_units の実データには触れない（表示側固定）方針の担保
RSpec.describe "出品フォーム価格表示", type: :model do
  let(:template) { File.read(Rails.root.join("app/views/listings/form/_price.haml")) }

  it "円マークの partial が入力欄より前に描画される" do
    currency_pos = template.index("price_currency")
    field_pos = template.index("price-field")
    expect(currency_pos).not_to be_nil
    expect(field_pos).not_to be_nil
    expect(currency_pos).to be < field_pos
  end

  it "単一単位の表示が per_million_tokens 固定である" do
    expect(template).to include('t(".per_million_tokens")')
  end

  it "単一単位の hidden field（実データ保存）は残る" do
    expect(template).to include('hidden_field_tag("listing[unit]"')
  end

  it "複数単位の選択肢（select）は動的表示のまま残る" do
    expect(template).to include(".js-listing-unit")
  end

  it "ja ロケールに per_million_tokens がある" do
    expect(I18n.t("listings.form.price.per_million_tokens", locale: :ja))
      .to eq("円 / 100万トークン")
  end

  it "en ロケールに per_million_tokens がある" do
    expect(I18n.t("listings.form.price.per_million_tokens", locale: :en))
      .to be_present
  end

  it ".price-currency が入力欄の前を想定した余白（margin-right）である" do
    scss = File.read(Rails.root.join("app/assets/stylesheets/main.scss"))
    currency_block = scss[/\.price-currency \{[^}]*\}/m]
    expect(currency_block).to include("margin-right")
    expect(currency_block).not_to include("margin-left")
  end
end
