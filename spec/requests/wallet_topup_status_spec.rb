# frozen_string_literal: true

require "spec_helper"

# Issue #62: Freemius 設定済みならチャージボタンは無効化されない（Issue #85 で「準備中」表記を廃止）。
#
# ChatPanel は起動時に GET /api/v1/wallet_topup/status を叩き、
# topup_enabled=false のときはボタンを無効化し、理由文（wallet_topup_unavailable_reason）を出す。
describe "チャージ可否のステータス API", type: :request do
  before(:all) do
    DatabaseCleaner.start
    @domain = "topup-status.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @person = FactoryBot.create(:person, username: "topupstatus", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)
    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def sign_in
    token = UserService::API::AuthTokens.create_login_token(@person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  it "Freemius の設定が揃っていれば topup_enabled=true と額面を返す" do
    allow(FreemiusClient).to receive(:configured?).and_return(true)
    allow(FreemiusPricing).to receive(:configured?).and_return(true)
    allow(FreemiusTopupPlans).to receive(:configured?).and_return(true)
    allow(FreemiusTopupPlans).to receive(:available_denominations)
      .and_return([{ plan_id: "74358", credit_jpy: 600 }])

    sign_in
    get "http://#{@domain}/api/v1/wallet_topup/status"

    expect(response.status).to eq(200)
    payload = JSON.parse(response.body)
    expect(payload["topup_enabled"]).to be(true)
    expect(payload["reason"]).to be_nil
    expect(payload["denominations"]).not_to be_empty
  end

  it "未設定なら topup_enabled=false と理由を返す（ボタン無効化の分岐）" do
    allow(FreemiusClient).to receive(:configured?).and_return(false)

    sign_in
    get "http://#{@domain}/api/v1/wallet_topup/status"

    expect(response.status).to eq(200)
    payload = JSON.parse(response.body)
    expect(payload["topup_enabled"]).to be(false)
    expect(payload["reason"]).to eq("payment_unconfigured")
  end
end
