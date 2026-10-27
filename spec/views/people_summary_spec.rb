# frozen_string_literal: true

require 'spec_helper'

# マイページのサマリー・サイドバー数値の短縮表示（Issue #95）。
#
# - 1,000 未満は全桁、1,000 以上は K/M/B 短縮＋title に正確値
# - 全文ページの request spec は webpack 未ビルド環境でアセット解決に落ちるため、
#   レイアウトなしのテンプレート描画で検証する
RSpec.describe "マイページの数値表示", type: :view do
  before(:all) do
    DatabaseCleaner.start
    @community = FactoryBot.create(:community, settings: { "locales" => ["ja"] })
    @owner = FactoryBot.create(:person, username: "summaryowner", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @owner, community: @community)
    @community.reload
    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @owner,
                                           default_run_mode: "run_online")
    @listing.update_column(:price_cents, 1000)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  before do
    allow_any_instance_of(ApplicationHelper).to receive(:missing_avatar).and_return("/images/missing.png")
    allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:current_user?).and_return(true)
  end

  def render_mypage(stats)
    service = Persons::ShowService.new(community: @community,
                                       params: { username: @owner.username },
                                       current_user: @owner)
    person_listings = Listing.where(community_id: @community.id, author_id: @owner.id, deleted: false)
    I18n.with_locale(:ja) do
      ApplicationController.render(
        template: "people/show",
        layout: false,
        assigns: {
          service: service,
          current_community: @community,
          current_user: @owner,
          raku_stats: stats,
          skill_listings: person_listings.includes(:listing_images)
                                         .order(Arel.sql("listings.sort_date DESC"))
                                         .paginate(page: 1, per_page: 20),
          closed_view: false,
          seller_earning_total_cents: 0,
          seller_earning_items: []
        }
      )
    end
  end

  it "1,000 以上は短縮表示し title に正確値を保持する" do
    html = render_mypage({ published: 1, total_tokens: 1_234_567, total_views: 23_456, avg_rating: nil })

    expect(html).to include("1.2M")
    expect(html).to include("23.5K")
    expect(html).to include('title="1,234,567"')
    expect(html).to include('title="23,456"')
  end

  it "1,000 未満は全桁表示する" do
    html = render_mypage({ published: 1, total_tokens: 999, total_views: 42, avg_rating: nil })

    expect(html).to include(">999<")
    expect(html).to include(">42<")
    expect(html).not_to include(">999K<")
  end
end
