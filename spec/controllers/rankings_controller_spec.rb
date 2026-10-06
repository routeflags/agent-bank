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
  end
end
