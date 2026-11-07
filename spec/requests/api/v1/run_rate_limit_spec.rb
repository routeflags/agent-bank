# frozen_string_literal: true

require 'rails_helper'

# 実行 API（POST /api/v1/personas/:id/run）のトークン単位レート制限（Issue #147）
#
# /api/v1 全体の 60 req / 5min（Issue #142）とは別のキー（`api/run`）で数える。
# テスト環境では config/initializers/rack_attack.rb が
# Rack::Attack.enabled = false にしているため、この describe の中だけで明示的に
# 有効化し、終了時に元の状態へ戻す（rate_limit_spec.rb と同じやり方）。
RSpec.describe "実行 API のレート制限（rack-attack）", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }

  def run_limit
    Rack::Attack::API_RUN_LIMIT
  end

  def clear_rack_attack_cache
    Rack::Attack.cache.store.delete_matched(/rack::attack/)
  end

  # 5 分の区切りをまたぐとカウンタが 0 に戻るため、時刻は区切りから離して固定する。
  around do |example|
    previous = Rack::Attack.enabled
    Rack::Attack.enabled = true
    clear_rack_attack_cache
    travel_to(Time.zone.parse("2026-01-01 12:02:00")) { example.run }
  ensure
    clear_rack_attack_cache
    Rack::Attack.enabled = previous
  end

  def bearer(raw_token)
    { "Authorization" => "Bearer #{raw_token}" }
  end

  # 実行 scope を持つトークン。それ以外は「認証は通るが対象が無い」404 で十分。
  def issue_token(owner: person)
    APIToken.issue!(person: owner, name: "MCP", scopes: %w[read run])
  end

  # 存在しないペルソナを指定して、レート制限だけを見る。
  # 存在する出品を渡すと AI 呼び出しと課金まで走ってしまう。
  def post_run(raw_token)
    post "/api/v1/personas/0/run",
         params: { message: "こんにちは" },
         headers: bearer(raw_token),
         as: :json
    response.status
  end

  def run_statuses(times, raw_token)
    Array.new(times) { post_run(raw_token) }
  end

  it "同一トークンで上限を超えると 429 と { error: rate_limited, scope: \"run\" } を返す" do
    _token, raw_token = issue_token

    statuses = run_statuses(run_limit + 1, raw_token)

    expect(statuses.first(run_limit).uniq).to eq([404])
    expect(statuses.last).to eq(429)
    expect(response.media_type).to eq("application/json")
    expect(JSON.parse(response.body))
      .to eq({ "error" => "rate_limited", "scope" => "run" })
  end

  it "トークンが違えば実行の枠も別に数える" do
    _token, raw_token = issue_token
    run_statuses(run_limit + 1, raw_token)
    expect(response.status).to eq(429)

    _other, other_raw_token = issue_token
    expect(post_run(other_raw_token)).to eq(404)
  end

  it "実行の枠は /api/v1 全体の枠と独立に数える" do
    _token, raw_token = issue_token
    run_statuses(run_limit + 1, raw_token)
    expect(response.status).to eq(429)

    # 実行 21 回を数えても、参照系（api/token の 60 回）は消費されていない。
    get "/api/v1/personas", headers: bearer(raw_token)
    expect(response.status).to eq(200)
  end
end
