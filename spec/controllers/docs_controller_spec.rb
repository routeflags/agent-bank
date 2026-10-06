# frozen_string_literal: true

require 'spec_helper'

describe DocsController, type: :controller do
  before(:each) do
    @community = FactoryBot.create(:community)
    @request.host = "#{@community.ident}.lvh.me"
    @request.env[:current_marketplace] = @community
  end

  describe "#index" do
    it "responds successfully" do
      get :index

      expect(response.status).to eq(200)
    end
  end
end
