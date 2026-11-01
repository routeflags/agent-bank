# frozen_string_literal: true

require 'spec_helper'

describe RankingsController, type: :controller do
  before(:each) do
    @community = FactoryBot.create(:community)
    @request.host = "#{@community.ident}.lvh.me"
    @request.env[:current_marketplace] = @community
  end

  describe "#index" do
    it "assigns open listings ordered by rating" do
      listing = FactoryBot.create(:listing, community_id: @community.id, avg_rating: 4.5)

      get :index

      expect(response.status).to eq(200)
      expect(assigns(:ranked_listings).map(&:id)).to eq([listing.id])
    end

    it "excludes closed listings" do
      FactoryBot.create(:listing, community_id: @community.id, open: false)

      get :index

      expect(response.status).to eq(200)
      expect(assigns(:ranked_listings)).to eq([])
    end

    it "returns an empty collection when the community has no listings" do
      get :index

      expect(assigns(:ranked_listings)).to eq([])
    end

    # ── Issue #106 Phase 2b: 並び順 ─────────────────────────
    # 評価は同点時のタイブレーク。実データ（販売数・閲覧数）を先に見る。
    # 以前は avg_rating が第一キーで、手動値を持つ実体のない出品が常に上位だった。
    it "販売数の降順を最優先する（評価が低くても売れている方が上）" do
      low  = FactoryBot.create(:listing, community_id: @community.id, total_sold: 1, avg_rating: 5.0)
      high = FactoryBot.create(:listing, community_id: @community.id, total_sold: 3, avg_rating: 3.0)

      get :index

      expect(assigns(:ranked_listings).map(&:id)).to eq([high.id, low.id])
    end

    it "販売数が同点なら閲覧数の降順" do
      few = FactoryBot.create(:listing, community_id: @community.id, total_sold: 2, times_viewed: 10)
      many = FactoryBot.create(:listing, community_id: @community.id, total_sold: 2, times_viewed: 50)

      get :index

      expect(assigns(:ranked_listings).map(&:id)).to eq([many.id, few.id])
    end

    it "販売数・閲覧数が同点なら評価の降順" do
      lower = FactoryBot.create(:listing, community_id: @community.id, total_sold: 2, times_viewed: 10,
                                          avg_rating: 3.0, reviews_count: 2)
      higher = FactoryBot.create(:listing, community_id: @community.id, total_sold: 2, times_viewed: 10,
                                           avg_rating: 4.5, reviews_count: 3)

      get :index

      expect(assigns(:ranked_listings).map(&:id)).to eq([higher.id, lower.id])
    end

    it "未評価（正規化後 0.0）は評価ありより下になる" do
      # 正規化タスク（lamprey:normalize_listing_ratings）適用後の状態を再現する。
      # 未適用の間は未評価の avg_rating に手動値（4.5 等）が残り得るが、それは
      # デプロイ直後の一時状態で、正規化で解消する（Phase 2a のリリース順序）。
      unrated = FactoryBot.create(:listing, community_id: @community.id, total_sold: 2, times_viewed: 10,
                                            avg_rating: 0.0, reviews_count: 0)
      rated = FactoryBot.create(:listing, community_id: @community.id, total_sold: 2, times_viewed: 10,
                                          avg_rating: 4.0, reviews_count: 1)

      get :index

      expect(assigns(:ranked_listings).map(&:id)).to eq([rated.id, unrated.id])
    end

    it "全キーが同点なら id 昇順で順序を決定的にする" do
      first  = FactoryBot.create(:listing, community_id: @community.id, total_sold: 0, times_viewed: 0)
      second = FactoryBot.create(:listing, community_id: @community.id, total_sold: 0, times_viewed: 0)

      get :index

      expect(assigns(:ranked_listings).map(&:id)).to eq([first.id, second.id])
    end
  end
end
