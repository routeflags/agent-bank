# frozen_string_literal: true

require 'spec_helper'

# 招待（invitations）のカバレッジ
describe "Invitations", type: :request do

  # test 環境は allow_forgery_protection=true のため、リクエストスペックの
  # POST は CSRF トークンなしで拒否される。このファイルの例のみ無効化する。
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end
  before(:all) do
    DatabaseCleaner.start

    @domain = "invitations-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @person = FactoryBot.create(:person, username: "inviteruser", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def login_as(person)
    t = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
    expect(response.status).to eq(302)
  end

  it "renders the invitation form" do
    login_as(@person)

    get "http://#{@domain}/ja/invitations/new"

    expect(response.status).to eq(200)
  end

  it "creates an invitation" do
    login_as(@person)

    expect {
      post "http://#{@domain}/ja/invitations",
           params: { invitation: { email: "friend@example.com", message: "一緒に使いましょう" } }
    }.to change(Invitation, :count).by(1)

    invitation = Invitation.last
    expect(invitation.email).to eq("friend@example.com")
    expect(invitation.inviter).to eq(@person)
  end
end
