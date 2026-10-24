# frozen_string_literal: true

require 'spec_helper'

# messages#create（取引会話への返信）のカバレッジ
describe "Messages create", type: :request do

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "messages-flow.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @seller = FactoryBot.create(:person, username: "msgseller", community_id: @community.id, member_of: @community)
    @buyer = FactoryBot.create(:person, username: "msgbuyer", community_id: @community.id, member_of: @community)
    @conversation = FactoryBot.create(:conversation, community: @community)
    FactoryBot.create(:participation, conversation: @conversation, person: @seller, is_starter: true)
    FactoryBot.create(:participation, conversation: @conversation, person: @buyer, is_starter: false)
    FactoryBot.create(:message, conversation: @conversation, sender: @seller, content: "初回メッセージ")
  end

  def sign_in(person)
    t = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  def post_reply(content)
    post "http://#{@domain}/ja/#{@buyer.username}/messages/#{@conversation.id}/messages",
         params: { message: { conversation_id: @conversation.id, content: content } }
  end

  it "creates a reply from a conversation participant" do
    sign_in(@buyer)
    expect { post_reply("返信メッセージです") }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:redirect)
  end

  it "creates a reply via JS format" do
    sign_in(@buyer)
    expect {
      post "http://#{@domain}/ja/#{@buyer.username}/messages/#{@conversation.id}/messages",
           params: { message: { conversation_id: @conversation.id, content: "JS返信" } },
           xhr: true
    }.to change(Message, :count).by(1)
    expect(response.status).to eq(200)
  end

  it "does not create a message when content is empty" do
    sign_in(@buyer)
    expect { post_reply("") }.not_to change(Message, :count)
    expect(response).to have_http_status(:redirect)
  end

  it "blocks non-participants from replying" do
    stranger = FactoryBot.create(:person, username: "msgstranger",
                                          community_id: @community.id, member_of: @community)
    sign_in(stranger)
    expect { post_reply("無関係な返信") }.not_to change(Message, :count)
    expect(response).to redirect_to(%r{\Ahttp://#{@domain}/})
  end

  it "redirects unauthenticated users to login" do
    expect { post_reply("未ログイン返信") }.not_to change(Message, :count)
    expect(response).to have_http_status(:redirect)
  end
end
