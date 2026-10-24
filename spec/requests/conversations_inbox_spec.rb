# frozen_string_literal: true

require 'spec_helper'

# メールボックス（会話一覧）の描画ガード
describe "Conversations inbox", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "inbox-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @person = FactoryBot.create(:person, username: "inboxuser", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)

    @conversation = FactoryBot.create(:conversation, community: @community)
    FactoryBot.create(:participation, conversation: @conversation, person: @person, is_starter: true)
    @counterparty = FactoryBot.create(:person, username: "counterparty", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @counterparty, community: @community)
    FactoryBot.create(:participation, conversation: @conversation, person: @counterparty, is_starter: false)
    FactoryBot.create(:message, conversation: @conversation, sender: @counterparty, content: "こんにちは")

    @other_person = FactoryBot.create(:person, username: "otherinbox", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @other_person, community: @community)
    @other_conversation = FactoryBot.create(:conversation, community: @community)
    FactoryBot.create(:participation, conversation: @other_conversation, person: @other_person, is_starter: true)
    @other_counterparty = FactoryBot.create(:person, username: "othercounter", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @other_counterparty, community: @community)
    FactoryBot.create(:participation, conversation: @other_conversation, person: @other_counterparty, is_starter: false)
    FactoryBot.create(:message, conversation: @other_conversation, sender: @other_counterparty, content: "別会話のメッセージ")
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "lists only the signed-in person's conversations" do
    t = UserService::API::AuthTokens.create_login_token(@person.id)[:token]

    # auth トークンはセッション確立のためのリダイレクトを伴うため2往復する
    get "http://#{@domain}/ja/#{@person.username}/inbox?auth=#{t}"
    expect(response.status).to eq(302)

    get "http://#{@domain}/ja/#{@person.username}/inbox"

    expect(response.status).to eq(200)
    # 一覧のタイトルは最終メッセージ本文（inbox_title）で表示される
    expect(response.body).to include("こんにちは")
    expect(response.body).not_to include("別会話のメッセージ")
  end
end
