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

  it "#117: カテゴリビジュアル（色ブロック＋英字ラベル＋絵文字）を描画する" do
    html = render_show(nil)
    expect(html).to include("raku-listing-visual")
    expect(html).to match(/raku-listing-visual--c\d/)
    expect(html).to include("raku-listing-visual__english")
    expect(html).to include("raku-listing-visual__swatch")
  end

  it "#117: タブの a11y 属性（tablist・tabpanel・aria-controls）を維持する" do
    html = render_show(nil)
    expect(html).to include('role="tablist"')
    expect(html).to include('role="tabpanel"')
    expect(html).to include('aria-controls="panel-overview"')
    expect(html).to include('aria-selected')
  end

  it "#90: カスタムフィールド値があるときは値を表示し空文言を出さない" do
    field = FactoryBot.create(:custom_text_field, required: false)
    TextFieldValue.create!(listing: @listing, question: field,
                           person: @owner, text_value: "Python と英語会話")
    panel = features_panel(render_show(@visitor))
    expect(panel).to include("Python と英語会話")
    expect(panel).not_to include(I18n.t("lamprey.listings.no_features", locale: :ja))
  end

  # ── Issue #106 Phase 1: ペルソナ評価の投稿導線 ──────────────
  def give_ai_reply(person, listing = @listing)
    session = FactoryBot.create(:chat_session, listing: listing, person_id: person.id)
    FactoryBot.create(:chat_message, chat_session: session, role: "assistant", seq: 2)
    session
  end

  it "#106: AI応答を受け取った利用者には評価フォームを出す" do
    person = FactoryBot.create(:person, username: "reviewform", community_id: @community.id)
    give_ai_reply(person)

    html = render_show(person)
    expect(html).to include("listing-review-form")
    expect(html).to include(I18n.t("lamprey.listings.review_form_title", locale: :ja))
    expect(html).to include("testimonial[stars]")
    expect(html).to include("testimonial[text]")
  end

  it "#106: 出品者本人には評価フォームを出さない" do
    give_ai_reply(@owner)

    expect(render_show(@owner)).not_to include("listing-review-form")
  end

  it "#106: AI応答のない利用者には評価フォームを出さない" do
    person = FactoryBot.create(:person, username: "reviewnone", community_id: @community.id)
    session = FactoryBot.create(:chat_session, listing: @listing, person_id: person.id)
    FactoryBot.create(:chat_message, chat_session: session, role: "user", seq: 1)

    expect(render_show(person)).not_to include("listing-review-form")
  end

  it "#106: 未ログインには評価フォームを出さない" do
    expect(render_show(nil)).not_to include("listing-review-form")
  end

  it "#106: 評価済みなら評価済み表示を出しフォームは出さない" do
    person = FactoryBot.create(:person, username: "reviewed", community_id: @community.id)
    give_ai_reply(person)
    Testimonial.create!(listing: @listing, author: person, receiver: @owner,
                        grade: 1.0, text: "good")

    html = render_show(person)
    expect(html).to include("listing-review-status")
    expect(html).to include(I18n.t("lamprey.listings.review_already_given", locale: :ja))
    expect(html).not_to include("listing-review-form")
  end

  # ── Issue #106 Phase 2b: 評価の表示（★ 4.2 (3)） ──────────────
  def give_rating(grade)
    reviewer = FactoryBot.create(:person, community_id: @community.id)
    Testimonial.create!(listing: @listing, author: reviewer, receiver: @owner, grade: grade)
    @listing.reload
  end

  it "#106 2b: 評価がある出品は評価値と件数を出す" do
    give_rating(0.75) # 4★ → avg_rating 4.0 / reviews_count 1

    html = render_show(nil)
    expect(html).to include("raku-price-box__rating")
    expect(html).to include("★ 4.0")
    expect(render_show(nil)).to include("(1)")
  end

  it "#106 2b: reviews_count が 0 なら手動 avg_rating があっても評価行を出さない" do
    # Phase 2a の正規化前の状態（手動値 4.5 / レビュー 0 件）を再現する。
    @listing.update_columns(avg_rating: 4.5, reviews_count: 0)

    html = render_show(nil)
    expect(html).not_to include("raku-price-box__rating")
    expect(html).not_to include("★")
    expect(html).not_to include(I18n.t("lamprey.listings.rating_none", locale: :ja))
  end

  it "#106 2b: 評価の有無で他の要素（価格・CTA）は変わらない" do
    html = render_show(nil)
    expect(html).to include("raku-price-box__amount")
    expect(html).to include("100万トークンあたりの単価です")
    expect(html).to include("raku-cta-btn")
  end

  # ── Issue #151: レビュー一覧といいね ──────────────────────
  def write_review(author, text: "とても良かったです")
    Testimonial.create!(listing: @listing, author: author, receiver: @owner,
                        grade: 1.0, text: text)
  end

  def other_person(username)
    FactoryBot.create(:person, username: username, community_id: @community.id)
  end

  it "#151: レビュー一覧を本文・件数つきで描画する" do
    write_review(other_person("reviewone"))

    html = render_show(@visitor)
    expect(html).to include('id="listing-reviews"')
    expect(html).to include(I18n.t("lamprey.listings.review_list_title", locale: :ja))
    expect(html).to include("とても良かったです")
    expect(html).to include("raku-review-like")
  end

  it "#151: 未ログインはボタンではなくログイン導線を出す" do
    write_review(other_person("reviewguest"))

    html = render_show(nil)
    expect(html).to include("raku-review-like--guest")
    expect(html).to include(I18n.t("lamprey.listings.review_like_login", locale: :ja))
    expect(html).not_to include('aria-pressed="false"')
  end

  it "#151: 自分のレビューにはいいねボタンを出さない" do
    write_review(@visitor)

    html = render_show(@visitor)
    expect(html).to include("とても良かったです")
    expect(html).not_to include("raku-review-like")
  end

  it "#151: いいね済みなら aria-pressed が true になり件数を出す" do
    review = write_review(other_person("reviewliked"))
    TestimonialLike.create!(testimonial: review, person: @visitor)

    html = render_show(@visitor)
    expect(html).to include('aria-pressed="true"')
    expect(html).to match(%r{raku-review-like__count[^>]*>\s*1\s*<})
  end

  it "#151: レビューが 0 件なら未レビュー文言を出し、ボタンも出さない" do
    html = render_show(nil)

    expect(html).to include(I18n.t("lamprey.listings.no_reviews", locale: :ja))
    expect(html).not_to include("raku-review-like")
  end
end
