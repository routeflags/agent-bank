# frozen_string_literal: true

require 'spec_helper'

# int_api/listing/bookings と int_api/listing/blocked_dates のカバレッジ
describe "Int API listing availability", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "intapi-listing.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @author = FactoryBot.create(:person, username: "intapiauth", community_id: @community.id, member_of: @community)
    @other = FactoryBot.create(:person, username: "intapiother", community_id: @community.id, member_of: @community)
    @listing = FactoryBot.create(:listing, community_id: @community.id, author: @author)
  end

  def sign_in(person)
    t = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  period = { start_on: "2026-10-01", end_on: "2026-10-31" }

  it "returns booked dates for the listing author" do
    sign_in(@author)
    get "http://#{@domain}/int_api/listings/#{@listing.id}/bookings", params: period
    expect(response.status).to eq(200)
    expect(JSON.parse(response.body)).to eq([])
  end

  it "forbids non-authors from reading booked dates" do
    sign_in(@other)
    get "http://#{@domain}/int_api/listings/#{@listing.id}/bookings", params: period
    expect(response.status).to eq(403)
  end

  it "returns blocked dates for the listing author" do
    sign_in(@author)
    get "http://#{@domain}/int_api/listings/#{@listing.id}/blocked_dates", params: period
    expect(response.status).to eq(200)
  end

  it "forbids non-authors from reading blocked dates" do
    sign_in(@other)
    get "http://#{@domain}/int_api/listings/#{@listing.id}/blocked_dates", params: period
    expect(response.status).to eq(403)
  end
end
