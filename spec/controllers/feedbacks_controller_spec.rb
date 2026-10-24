# frozen_string_literal: true

require 'spec_helper'

describe FeedbacksController, type: :controller do
  before(:each) do
    @community = FactoryBot.create(:community)
    @request.host = "#{@community.ident}.lvh.me"
    @request.env[:current_marketplace] = @community
  end

  describe "#new" do
    it "renders the feedback form" do
      get :new

      expect(response.status).to eq(200)
    end
  end

  describe "#create" do
    it "creates a feedback with valid attributes" do
      expect {
        post :create, params: { feedback: { email: "someone@example.com", content: "Nice site", url: "/spec" } }
      }.to change(Feedback, :count).by(1)
    end

    it "re-renders the form when the feedback is invalid" do
      expect {
        post :create, params: { feedback: { email: "someone@example.com", content: "" } }
      }.not_to change(Feedback, :count)

      expect(response).to have_http_status(:ok).or have_http_status(:unprocessable_entity)
    end
  end
end
