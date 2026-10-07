# frozen_string_literal: true

require 'spec_helper'

# プロフィールから新規メッセージ送信（person_messages#create）のカバレッジ
describe "Person messages", type: :request do

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

    @domain = "person-messages-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @sender = FactoryBot.create(:person, username: "msgsender", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @sender, community: @community)
    @recipient = FactoryBot.create(:person, username: "msgrecipient", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @recipient, community: @community)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  it "starts a new conversation with the recipient" do
    t = UserService::API::AuthTokens.create_login_token(@sender.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
    expect(response.status).to eq(302)

    expect {
      post "http://#{@domain}/ja/#{@recipient.username}/person_messages",
           params: { conversation: { message_attributes: { content: "こんにちは、依頼があります" } } }
    }.to change(Conversation, :count).by(1)
      .and change(Message, :count).by(1)

    expect(response).to redirect_to(person_path(@recipient))
    conversation = Conversation.last
    expect(conversation.participants).to include(@sender, @recipient)
  end

  it "does not create a conversation when content is empty" do
    t = UserService::API::AuthTokens.create_login_token(@sender.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"

    expect {
      post "http://#{@domain}/ja/#{@recipient.username}/person_messages",
           params: { conversation: { message_attributes: { content: "" } } }
    }.not_to change(Conversation, :count)

    expect(response).to redirect_to(%r{\Ahttp://#{@domain}/\z})
  end
end
