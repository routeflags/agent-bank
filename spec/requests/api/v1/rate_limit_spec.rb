# frozen_string_literal: true

require 'rails_helper'

# /api/v1 のトークン単位レート制限（rack-attack、Issue #142）
#
# テスト環境では config/initializers/rack_attack.rb が
# Rack::Attack.enabled = false にしているため、この describe の中だけで明示的に
# 有効化し、終了時に元の状態へ戻す。
RSpec.describe "API のレート制限（rack-attack）", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }

  def api_limit
    Rack::Attack::API_TOKEN_LIMIT
  end

  # throttle カウンタだけを消す（Rack::Attack.reset! は文字列 matcher で
  # ActiveSupport 8 では失敗するため、Regexp で消す）
  def clear_rack_attack_cache
    Rack::Attack.cache.store.delete_matched(/rack::attack/)
  end

  # rack-attack のカウンタキーは「period ごとの epoch 区切り」を含むため、
  # 上限回数のリクエスト中に区切り（5 分）をまたぐとカウントが 0 に戻り、
  # 429 にならないことがある。時刻を区切りから十分離した値に固定して
  # 判定を決定的にする。
  around do |example|
    previous = Rack::Attack.enabled
    Rack::Attack.enabled = true
    clear_rack_attack_cache
    travel_to(Time.zone.parse("2026-01-01 12:02:00")) { example.run }
  ensure
    clear_rack_attack_cache
    Rack::Attack.enabled = previous
  end

  def issue_token(owner: person)
    APIToken.issue!(person: owner, name: "MCP", scopes: ["read"])
  end

  def bearer(raw_token)
    { "Authorization" => "Bearer #{raw_token}" }
  end

  def statuses_for(requests)
    Array.new(requests) do
      get "/api/v1/chat_sessions", headers: bearer(@raw_token)
      response.status
    end
  end

  it "同一トークンで上限を超えると 429 と { error: rate_limited } を返す" do
    _token, @raw_token = issue_token

    statuses = statuses_for(api_limit + 1)

    expect(statuses.first(api_limit).uniq).to eq([200])
    expect(statuses.last).to eq(429)
    expect(response.media_type).to eq("application/json")
    expect(JSON.parse(response.body)).to eq({ "error" => "rate_limited" })
  end

  it "トークンが違えば別のキーで数える（影響を受けない）" do
    _token, @raw_token = issue_token
    statuses_for(api_limit + 1)
    expect(response.status).to eq(429)

    _other, other_raw_token = issue_token
    get "/api/v1/chat_sessions", headers: bearer(other_raw_token)

    expect(response.status).to eq(200)
  end

  it "Bearer が無いリクエストは IP で数える" do
    statuses = Array.new(api_limit + 1) do
      get "/api/v1/chat_sessions" # 未認証。カウントは認証前に走る
      response.status
    end

    expect(statuses.first(api_limit).uniq).to eq([401])
    expect(statuses.last).to eq(429)
    expect(JSON.parse(response.body)).to eq({ "error" => "rate_limited" })
  end

  it "IP の制限を使い切ってもトークン付きリクエストは通る" do
    Array.new(api_limit + 1) { get "/api/v1/chat_sessions" }
    expect(response.status).to eq(429)

    _token, raw_token = issue_token
    get "/api/v1/chat_sessions", headers: bearer(raw_token)

    expect(response.status).to eq(200)
  end
end
