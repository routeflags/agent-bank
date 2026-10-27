# frozen_string_literal: true

require 'spec_helper'

# カテゴリビジュアル（色ブロック＋英字ラベル＋絵文字）の単一供給（Issue #117）。
#
# 対応表は HomepageHelper の2定数だけに持ち、出品詳細テンプレートは
# listing_category_visual の呼び出しで供給を受ける。テンプレート側への
# 二重定義の後退をソース断面でも担保する。
RSpec.describe HomepageHelper, type: :helper do
  before(:all) do
    DatabaseCleaner.start
    @community = FactoryBot.create(:community, settings: { "locales" => ["ja"] })
    @top = FactoryBot.create(:category, community: @community, icon: "text")
    # url は before_save の uniq_url で採番されるため直接指定する。
    @top.update_column(:url, "text-generation")
    @top.translations.create!(locale: "en", name: "Text Generation")
    @child = FactoryBot.create(:category, community: @community, icon: "edit",
                                          parent_id: @top.id)
    @child.update_column(:url, "writing-assistant")
    @child.translations.create!(locale: "en", name: "Writing Assistant")
    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "パレットは8色で Issue 指定の Gold・赤を含む" do
    expect(HomepageHelper::CATEGORY_VISUAL_COLORS.size).to eq(8)
    expect(HomepageHelper::CATEGORY_VISUAL_COLORS).to include("#dfb560", "#ec1029")
  end

  it "サブカテゴリは上位の絵文字・英字ラベルに寄せる" do
    visual = helper.category_visual(@child)
    expect(visual[:emoji]).to eq("📝")
    expect(visual[:english_label]).to eq("TEXT GENERATION")
    expect(visual[:name]).not_to be_empty
  end

  it "同じカテゴリは同じ色になる（決定的）" do
    first = helper.category_visual(@child)
    second = helper.listing_category_visual(double(category: @child))
    expect(second[:color_index]).to eq(first[:color_index])
    expect(second[:color]).to eq(first[:color])
  end

  it "カテゴリ無しはフォールバックを返す" do
    visual = helper.listing_category_visual(double(category: nil))
    expect(visual[:english_label]).to eq("PERSONA")
    expect(visual[:emoji]).to eq("🤖")
    expect(visual[:color_index]).to eq(0)
  end

  it "未登録アイコンはデフォルト絵文字に倒す" do
    unknown = FactoryBot.create(:category, community: @community,
                                           icon: "no-such-icon")
    unknown.update_column(:url, "mystery-box")
    unknown.translations.create!(locale: "en", name: "Mystery Box")
    expect(helper.category_visual(unknown)[:emoji]).to eq("🤖")
  end

  it "show テンプレートはヘルパー呼び出しで供給を受け定義を二重に持たない" do
    show = File.read(Rails.root.join("app/views/listings/show.haml"))
    expect(show).to include("listing_category_visual")
    HomepageHelper::CATEGORY_VISUAL_COLORS.each do |hex|
      expect(show).not_to include(hex)
    end
    # 英字ラベルの直書き（大文字スラッグ）もテンプレートに置かない。
    expect(show).not_to match(/TEXT GENERATION|WRITING ASSISTANT/)
  end
end
