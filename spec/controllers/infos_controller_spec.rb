# frozen_string_literal: true

require 'spec_helper'

describe InfosController, type: :controller do
  before(:each) do
    @community = FactoryBot.create(:community)
    @request.host = "#{@community.ident}.lvh.me"
    @request.env[:current_marketplace] = @community
  end

  %w[about how_to_use terms privacy].each do |action|
    describe "##{action}" do
      it "responds successfully" do
        get action.to_sym

        expect(response.status).to eq(200)
      end
    end
  end
end
