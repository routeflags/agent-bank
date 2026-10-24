# frozen_string_literal: true

require 'spec_helper'

# public エンドポイント（i18n#change_locale / topbar_api#props /
# community_memberships）のカバレッジ
describe "Public endpoints", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "public-endpoints.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @user = FactoryBot.create(:person, username: "publicuser", locale: "ja",
                                       community_id: @community.id, member_of: @community)
  end

  def sign_in(person)
    t = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  # i18n#change_locale
  it "changes locale for a signed-in user" do
    sign_in(@user)
    get "http://#{@domain}/change_locale", params: { locale: "en", redirect_uri: "/en" }
    expect(response).to have_http_status(:redirect)
    expect(@user.reload.locale).to eq("en")
  end

  it "redirects anonymous users on locale change" do
    get "http://#{@domain}/change_locale", params: { locale: "en", redirect_uri: "/en" }
    expect(response).to have_http_status(:redirect)
  end

  # topbar_api#props
  it "returns topbar props JSON for anonymous users" do
    get "http://#{@domain}/ui_api/topbar_props", params: { locale: "ja" }
    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    expect(body["marketplaceContext"]["marketplaceId"]).to eq(@community.id)
    expect(body).to have_key("props")
  end

  it "returns topbar props JSON with logged-in user" do
    sign_in(@user)
    get "http://#{@domain}/ui_api/topbar_props", params: { locale: "ja" }
    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    expect(body["marketplaceContext"]["loggedInUsername"]).to eq(@user.username)
  end

  # community_memberships
  def create_pending_membership(status: "pending_consent", consent: nil)
    person = FactoryBot.create(:person, username: "pending#{SecureRandom.hex(3)}",
                                        community_id: @community.id)
    FactoryBot.create(:community_membership, person: person, community: @community,
                                             status: status, consent: consent)
    person
  end

  it "renders pending consent form" do
    person = create_pending_membership
    sign_in(person)
    get "http://#{@domain}/community_memberships/pending_consent"
    expect(response.status).to eq(200)
  end

  it "accepts consent and joins the community" do
    person = create_pending_membership
    sign_in(person)
    post "http://#{@domain}/community_memberships/give_consent",
         params: { form: { consent: "on", email: person.emails.first.address } }
    expect(response).to have_http_status(:redirect)
    membership = CommunityMembership.find_by(person_id: person.id, community_id: @community.id)
    expect(membership.status).to eq("accepted")
  end

  it "re-renders consent form when consent is missing" do
    person = create_pending_membership
    sign_in(person)
    post "http://#{@domain}/community_memberships/give_consent", params: { form: {} }
    expect(response.status).to eq(200)
    membership = CommunityMembership.find_by(person_id: person.id, community_id: @community.id)
    expect(membership.status).to eq("pending_consent")
  end

  it "checks invitation code via JSON" do
    person = create_pending_membership
    sign_in(person)
    get "http://#{@domain}/community_memberships/check_invitation_code",
        params: { form: { invitation_code: "SOME-CODE" } }
    expect(response.status).to eq(200)
  end

  it "checks email availability via JSON" do
    person = create_pending_membership
    sign_in(person)
    get "http://#{@domain}/community_memberships/check_email_availability_and_validity",
        params: { form: { email: "someone-new-#{SecureRandom.hex(3)}@example.com" } }
    expect(response.status).to eq(200)
    expect(JSON.parse(response.body)).to eq(true)
  end

  it "renders confirmation pending page" do
    person = create_pending_membership(status: "pending_email_confirmation")
    sign_in(person)
    get "http://#{@domain}/ja/confirmation_pending"
    expect(response.status).to eq(200)
  end

  it "renders access denied page" do
    person = create_pending_membership
    sign_in(person)
    get "http://#{@domain}/community_memberships/access_denied"
    expect(response.status).to eq(200)
  end
end
