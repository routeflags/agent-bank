# frozen_string_literal: true

require 'spec_helper'

# 出品詳細テンプレートの描画回帰（Issue #93・#89・#90）。
#
# 全文ページの request spec は webpack 未ビルド環境でアセット解決に落ちるため、
# レイアウトなしのテンプレート描画で検証する。アバター画像は
# missing_avatar をスタブしてアセット層を分離する。
RSpec.describe "出品詳細テンプレート", type: :view do
  before(:all) do
    DatabaseCleaner.start
    @community = FactoryBot.create(:community, settings: { "locales" => ["ja"] })
    @owner = FactoryBot.create(:person, username: "showowner", community_id: @community.id)
    @visitor = FactoryBot.create(:person, username: "showvisitor", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @owner, community: @community)
    FactoryBot.create(:community_membership, person: @visitor, community: @community)
    @community.reload
    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @owner,
                                           title: "はるか — お悩み相談室",
                                           default_run_mode: "run_online")
    # #93: レガシー形状の unit_type が残っている出品
    @listing.update_column(:unit_type, "hour")
    @listing.update_column(:price_cents, 1000)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  before do
    allow_any_instance_of(ApplicationHelper).to receive(:missing_avatar).and_return("/images/missing.png")
    # request.env[:current_marketplace] が無い描画のためパス解決だけ固定する
    allow_any_instance_of(ApplicationHelper).to receive(:search_path).and_return("/search")
    allow_any_instance_of(ApplicationHelper).to receive(:landing_page_path).and_return("/")
  end

  def render_show(current_user)
    # 関連キャッシュ(@listing.custom_field_values のメモ化)で他 example の
    # 状態を引きずらないよう描画前に取り直す。
    @listing.reload
    # ApplicationController.render の assigns は view の ivar に載るが、
    # logged_in? は controller の ivar を読むため述語だけスタブする。
    allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_return(current_user.present?)
    allow_any_instance_of(ApplicationController).to receive(:current_user?).and_return(false)
    if current_user
      user = current_user
      allow_any_instance_of(ApplicationController).to receive(:current_user?).with(user).and_return(true)
    end
    presenter = ListingPresenter.new(@listing, @community, {}, current_user)
    I18n.with_locale(:ja) do
      ApplicationController.render(
        template: "listings/show",
        layout: false,
        assigns: {
          listing: @listing,
          listing_presenter: presenter,
          current_community: @community,
          current_user: current_user
        }
      )
    end
  end

  def features_panel(body)
    body[/data-raku-panel="features".*?(?=data-raku-panel=)/m] || ""
  end

  it "#93: 時間単位（raku-price-box__unit）を描画しない" do
    expect(render_show(nil)).not_to include("raku-price-box__unit")
  end

  it "#93: 単価の注記は「100万トークンあたり」の正表記になる" do
    expect(render_show(nil)).to include("100万トークンあたりの単価です")
  end

  it "#89: ChatPanelApp に出品タイトルを persona_name として渡す" do
    html = render_show(nil)
    expect(html).to include("ChatPanelApp")
    expect(html).to include("はるか — お悩み相談室")
  end

  it "#90: 本人には機能空パネルで編集導線を出す" do
    panel = features_panel(render_show(@owner))
    expect(panel).to include(I18n.t("lamprey.listings.no_features", locale: :ja))
    expect(panel).to include(I18n.t("listings.edit_links.edit_listing", locale: :ja))
  end

  it "#90: 第三者には編集導線を出さない" do
    panel = features_panel(render_show(@visitor))
    expect(panel).to include(I18n.t("lamprey.listings.no_features", locale: :ja))
    expect(panel).not_to include(I18n.t("listings.edit_links.edit_listing", locale: :ja))
  end

  it "#90: カスタムフィールド値があるときは値を表示し空文言を出さない" do
    field = FactoryBot.create(:custom_text_field, required: false)
    TextFieldValue.create!(listing: @listing, question: field,
                           person: @owner, text_value: "Python と英語会話")
    panel = features_panel(render_show(@visitor))
    expect(panel).to include("Python と英語会話")
    expect(panel).not_to include(I18n.t("lamprey.listings.no_features", locale: :ja))
  end
end
