# frozen_string_literal: true

require 'spec_helper'

# admin2/emails 配下（outgoing_emails / welcome_emails / email_users）のカバレッジ
describe "Admin2 email settings", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-emails.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @admin = FactoryBot.create(:person, username: "admin2mails",
                                        community_id: @community.id, member_of: @community, member_is_admin: true)
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  # outgoing emails
  it "renders outgoing emails index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/emails/custom-outgoing-address"
    expect([200, 302]).to include(response.status)
  end

  # welcome emails
  it "renders welcome emails index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/emails/welcome-email"
    expect(response.status).to eq(200)
  end

  it "updates welcome email settings" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/emails/welcome-email/update_email"
    expect(response.status).to eq(200)
  end

  it "sends a test welcome email" do
    admin_sign_in
    patch "http://#{@domain}/ja/admin/emails/welcome-email/update_email", params: { test_email: "1" }
    expect(response.status).to eq(200)
  end

  # email users
  it "renders email users index" do
    admin_sign_in
    get "http://#{@domain}/ja/admin/emails/compose-email"
    expect(response.status).to eq(200)
  end

  it "enqueues a test email job" do
    admin_sign_in
    expect {
      post "http://#{@domain}/ja/admin/emails/compose-email",
           params: { email: { content: "テスト配信内容", locale: "ja" }, test_email: "1" }
    }.to change(Delayed::Job, :count).by(1)
    expect(response.status).to eq(200)
  end

  it "enqueues a member email batch job" do
    admin_sign_in
    expect {
      post "http://#{@domain}/ja/admin/emails/compose-email",
           params: { email: { content: "一斉配信", locale: "ja", recipients: "all" } }
    }.to change(Delayed::Job, :count).by(1)
    expect(response.status).to eq(200)
  end

  it "returns unprocessable on email content error" do
    admin_sign_in
    post "http://#{@domain}/ja/admin/emails/compose-email", params: {}
    expect(response.status).to eq(422)
  end
end
