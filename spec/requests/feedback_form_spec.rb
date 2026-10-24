# frozen_string_literal: true

require 'spec_helper'

# お問い合わせフォーム（feedbacks）の描画・投稿ガード
describe "Feedback form", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "feedback-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @person = FactoryBot.create(:person, username: "feedbackuser", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "renders the feedback form" do
    get "http://#{@domain}/ja/user_feedbacks/new"

    expect(response.status).to eq(200)
  end

  it "creates a feedback on valid submission" do
    expect {
      post "http://#{@domain}/ja/user_feedbacks",
           params: { feedback: { email: "someone@example.com", content: "Great marketplace", url: "/spec" } }
    }.to change(Feedback, :count).by(1)
  end
end
