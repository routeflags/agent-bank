# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::ChatAttachments", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person)    { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing)   { FactoryBot.create(:listing, community_id: community.id, author: person) }
  let(:chat_session) { FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id) }

  def image_upload(content_type: "image/png", filename: "test.png")
    data = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    Rack::Test::UploadedFile.new(StringIO.new(data), content_type, original_filename: filename)
  end

  describe "POST /api/v1/chat_sessions/:chat_session_id/attachments" do
    context "セッション所有者が画像をアップロード" do
      before { sign_in(person) }

      it "returns 201 with attachment id and url" do
        post "/api/v1/chat_sessions/#{chat_session.id}/attachments",
             params: { image: image_upload }

        expect(response.status).to eq(201)
        json = JSON.parse(response.body)
        expect(json["id"]).to be_present
        expect(json["url"]).to be_present
      end

      it "persists a ChatAttachment linked to the session and person" do
        expect {
          post "/api/v1/chat_sessions/#{chat_session.id}/attachments",
               params: { image: image_upload }
        }.to change(ChatAttachment, :count).by(1)

        attachment = ChatAttachment.last
        expect(attachment.chat_session_id).to eq(chat_session.id)
        expect(attachment.person_id).to eq(person.id)
      end
    end

    context "別のユーザーのセッションへアップロード" do
      before { sign_in(other_person) }

      it "returns 404" do
        post "/api/v1/chat_sessions/#{chat_session.id}/attachments",
             params: { image: image_upload }

        expect(response.status).to eq(404)
      end
    end

    context "未ログイン" do
      it "returns 401" do
        post "/api/v1/chat_sessions/#{chat_session.id}/attachments",
             params: { image: image_upload }

        expect(response.status).to eq(401)
      end
    end

    context "不正なファイル種別" do
      before { sign_in(person) }

      it "returns 422" do
        post "/api/v1/chat_sessions/#{chat_session.id}/attachments",
             params: { image: image_upload(content_type: "text/plain", filename: "evil.txt") }

        expect(response.status).to eq(422)
      end
    end
  end

  describe "セッションshowでの添付解決" do
    it "returns attachment url for messages with metadata.attachment_id" do
      sign_in(person)
      post "/api/v1/chat_sessions/#{chat_session.id}/attachments",
           params: { image: image_upload }
      expect(response.status).to eq(201)
      attachment = ChatAttachment.last

      chat_session.chat_messages.create!(
        content: "添付付きメッセージ",
        role: "user",
        sender_type: "Person",
        sender_id: person.id,
        seq: 1,
        metadata: { "attachment_id" => attachment.id }
      )

      get "/api/v1/chat_sessions/#{chat_session.id}"
      expect(response.status).to eq(200)
      json = JSON.parse(response.body)
      message = json["chat_session"]["messages"].first
      expect(message["attachment"]).to be_present
      expect(message["attachment"]["id"]).to eq(attachment.id)
      expect(message["attachment"]["url"]).to be_present
    end
  end
end
