# frozen_string_literal: true

require 'spec_helper'

# api/token throttle のキー生成（Issue #142）
#
# 生トークンはキーにもログにも残さない（digest を使う）ことを、リクエストを
# 介さずに固定する。
describe "Rack::Attack の API 用キー" do
  def request_for(path, authorization: nil)
    env = Rack::MockRequest.env_for(path)
    env["HTTP_AUTHORIZATION"] = authorization if authorization
    Rack::Request.new(env)
  end

  describe ".api_path?" do
    it "/api/v1 配下を対象にする" do
      expect(Rack::Attack.api_path?("/api/v1/tokens")).to eq true
      expect(Rack::Attack.api_path?("/api/v1")).to eq true
      expect(Rack::Attack.api_path?("/api/v1/chat_sessions/1")).to eq true
    end

    it "類似パスや一般画面は対象外にする" do
      expect(Rack::Attack.api_path?("/api/v10/tokens")).to eq false
      expect(Rack::Attack.api_path?("/api/v2/tokens")).to eq false
      expect(Rack::Attack.api_path?("/ja")).to eq false
      expect(Rack::Attack.api_path?("/ja/api/v1/tokens")).to eq false
      expect(Rack::Attack.api_path?("/")).to eq false
      expect(Rack::Attack.api_path?("")).to eq false
    end
  end

  describe ".api_throttle_key" do
    it "Bearer トークンは digest で数え、生トークンを含めない" do
      raw_token = "secret-raw-token"
      key = Rack::Attack.api_throttle_key(
        request_for("/api/v1/tokens", authorization: "Bearer #{raw_token}")
      )

      expect(key).to eq("token:#{APIToken.digest(raw_token)}")
      expect(key).not_to include(raw_token)
    end

    it "Token スキームも同じく digest で数える" do
      raw_token = "secret-raw-token"
      key = Rack::Attack.api_throttle_key(
        request_for("/api/v1/tokens", authorization: "Token #{raw_token}")
      )

      expect(key).to eq("token:#{APIToken.digest(raw_token)}")
    end

    it "Bearer が無ければ IP で数える" do
      request = request_for("/api/v1/tokens")
      request.env["action_dispatch.remote_ip"] = "198.51.100.7"

      expect(Rack::Attack.api_throttle_key(request)).to eq("ip:198.51.100.7")
    end

    it "Bearer の値が空なら IP で数える" do
      request = request_for("/api/v1/tokens", authorization: "Bearer ")
      request.env["action_dispatch.remote_ip"] = "198.51.100.8"

      expect(Rack::Attack.api_throttle_key(request)).to eq("ip:198.51.100.8")
    end
  end
end
