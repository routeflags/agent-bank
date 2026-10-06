# frozen_string_literal: true

require 'spec_helper'

# 会話スレッド詳細（conversations#show）の描画ガード:
# 参加者のみ閲覧でき、メッセージが描画され、既読が更新される。
describe "Conversation thread", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "thread-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @person = FactoryBot.create(:person, username: "threaduser", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)

    @counterparty = FactoryBot.create(:person, username: "threadcounter", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @counterparty, community: @community)

    @conversation = FactoryBot.create(:conversation, community: @community)
    FactoryBot.create(:participation, conversation: @conversation, person: @person, is_starter: true)
    FactoryBot.create(:participation, conversation: @conversation, person: @counterparty, is_starter: false)
    FactoryBot.create(:message, conversation: @conversation, sender: @counterparty, content: "スレッドのメッセージ")
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def thread_url(person)
    "http://#{@domain}/ja/#{person.username}/messages/received/#{@conversation.id}"
  end

  it "renders the thread for a participant and marks it as read" do
    t = UserService::API::AuthTokens.create_login_token(@person.id)[:token]

    get "#{thread_url(@person)}?auth=#{t}"
    expect(response.status).to eq(302)

    get thread_url(@person)

    expect(response.status).to eq(200)
    expect(response.body).to include("スレッドのメッセージ")
    participation = @conversation.participations.find_by(person: @person)
    expect(participation.is_read).to eq(true)
  end

  it "redirects non-participants away from the thread" do
    stranger = FactoryBot.create(:person, username: "threadstranger", community_id: @community.id)
    FactoryBot.create(:community_membership, person: stranger, community: @community)
    t = UserService::API::AuthTokens.create_login_token(stranger.id)[:token]

    get "#{thread_url(@person)}?auth=#{t}"
    expect(response.status).to eq(302)

    get thread_url(@person)

    expect(response).to redirect_to(%r{\Ahttp://#{@domain}/\z})
  end
end
