# frozen_string_literal: true

require 'rails_helper'

# アクセシビリティ残件の回帰（Issue #83）。
# 対応済み項目の後退と、今回の残件修正の契約をソース断面で担保する。
RSpec.describe "アクセシビリティ残件", type: :model do
  let(:show) { File.read(Rails.root.join("app/views/listings/show.haml")) }
  let(:mypage) { File.read(Rails.root.join("app/views/people/show.haml")) }
  let(:settings) { File.read(Rails.root.join("app/views/settings/show.haml")) }
  let(:stripe) { File.read(Rails.root.join("app/assets/javascripts/thumbnail_stripe.js")) }

  it "出品詳細に h1 がある" do
    expect(show).to include("%h1.raku-breadcrumb__current")
  end

  it "タブは aria-controls・tabpanel・roving tabindex で関連付く" do
    expect(show).to include('"aria-controls": "panel-overview"')
    expect(show).to include('role: "tabpanel"')
    expect(show).to include('"aria-labelledby": "tab-features"')
  end

  it "RakuTabs は修飾キー付き矢印をブラウザに譲る" do
    expect(show).to include("e.altKey || e.ctrlKey || e.metaKey")
  end

  it "サムネイル img に名前（出品タイトル）がある" do
    expect(show).to match(/image-thumbnail-template.*alt: @listing\.title/m)
  end

  it "サムネイルの選択はキーボード操作できる" do
    expect(stripe).to include('attr("role", "button")')
    expect(stripe).to include("keydown")
  end

  it "画像ナビ（前・次）に accessible name がある" do
    expect(show).to include("t('lamprey.listings.prev_image')")
    expect(show).to include("t('lamprey.listings.next_image')")
    expect(I18n.t("lamprey.listings.prev_image", locale: :ja)).to eq("前の画像")
    expect(I18n.t("lamprey.listings.next_image", locale: :ja)).to eq("次の画像")
  end

  it "マイページは h1・nav・テーブルの scope を持つ" do
    expect(mypage).to include("%h1.raku-profile__name")
    expect(mypage).to include("%nav.raku-sidebar__nav")
    expect(mypage).to include('%th{scope: "col"}')
  end

  it "マイページの操作ボタンに aria-label がある" do
    expect(mypage).to include("aria: {label: t('lamprey.mypage.action_edit')}")
  end

  it "スキル一覧のサムネイルは装飾扱い（直後に同名リンクがある）" do
    expect(mypage).to match(/raku-table__skill-thumb\{[^}]*alt: ""/m)
  end

  it "settings の装飾アイコンは aria-hidden で、説明文は入力に紐付く" do
    expect(settings).not_to include("%span.alert-box-icon\n")
    expect(settings).to include('"aria-describedby" => "person_street_address_description"')
    expect(settings).to include('"aria-describedby" => "person_image_description"')
    expect(settings).to include('"aria-describedby" => "person_description_description"')
  end
end
