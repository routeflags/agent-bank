# frozen_string_literal: true

require 'spec_helper'

# メール確認（confirmations）のカバレッジ
describe "Confirmations", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "confirmations-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @person = FactoryBot.create(:person, username: "confirmtarget", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "redirects on an unknown confirmation token" do
    get "http://#{@domain}/ja/people/confirmation?confirmation_token=no-such-token-123"

    expect(response).to have_http_status(:redirect).or have_http_status(:not_found)
  end
end
