# frozen_string_literal: true

require 'spec_helper'

# admin2/users/api-tokens（MCP 用パーソナルアクセストークンの一覧・失効、Issue #147）
describe "Admin2 API tokens", type: :request do
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "admin2-tokens.custom.org"
    @community = FactoryBot.create(:community,
                                                domain: @domain, use_domain: true,
                                                settings: { "locales" => ["ja"] })
    @community.community_customizations.find_or_create_by(locale: "ja")
    @admin = FactoryBot.create(:person, username: "admin2tokens",
                                        community_id: @community.id,
                                        member_of: @community, member_is_admin: true)
    @member = FactoryBot.create(:person, username: "mcpmember",
                                         community_id: @community.id,
                                         member_of: @community)
  end

  # 各例で新しいトークンを発行する（失効の検証が他の例に筒抜けしないように）。
  before do
    @token, @raw_token = APIToken.issue!(person: @member, name: "Claude Desktop", scopes: %w[read run])
  end

  def admin_sign_in
    t = UserService::API::AuthTokens.create_login_token(@admin.id)[:token]
    get "http://#{@domain}/ja?auth=#{t}"
  end

  def bearer(raw_token)
    { "Authorization" => "Bearer #{raw_token}" }
  end

  it "一覧に会員名・名前・スコープ・日次上限・状態を出す" do
    admin_sign_in

    get "http://#{@domain}/ja/admin/users/api-tokens"

    expect(response.status).to eq(200)
    expect(response.body).to include("Claude Desktop")
    expect(response.body).to include("Proto Testro")
    expect(response.body).to include("read, run")
    expect(response.body).to include("500 円 / 日")
    expect(response.body).to include("有効")
    # 平文も digest も出さない。
    expect(response.body).not_to include(@raw_token)
    expect(response.body).not_to include(@token.token_digest)
  end

  it "別のマーケットプレイスの会員のトークンは一覧に出さない" do
    other_community = FactoryBot.create(:community)
    stranger = FactoryBot.create(:person, community_id: other_community.id)
    FactoryBot.create(:community_membership, person: stranger, community: other_community)
    APIToken.issue!(person: stranger, name: "Other Shop Token", scopes: ["read"])

    admin_sign_in
    get "http://#{@domain}/ja/admin/users/api-tokens"

    expect(response.status).to eq(200)
    expect(response.body).not_to include("Other Shop Token")
  end

  it "失効ボタンで失効できる" do
    admin_sign_in

    expect do
      post "http://#{@domain}/ja/admin/users/api-tokens/#{@token.id}/revoke"
    end.to change { @token.reload.revoked? }.from(false).to(true)

    expect(response).to redirect_to(%r{/admin/users/api-tokens})
    expect(flash[:notice]).to be_present
  end

  it "失効したトークンでは API が 401 になる" do
    get "http://#{@domain}/api/v1/tokens", headers: bearer(@raw_token)
    expect(response.status).to eq(200)

    admin_sign_in
    post "http://#{@domain}/ja/admin/users/api-tokens/#{@token.id}/revoke"

    get "http://#{@domain}/api/v1/tokens", headers: bearer(@raw_token)
    expect(response.status).to eq(401)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_token")
  end

  it "別のマーケットプレイスのトークンは失効できない" do
    other_community = FactoryBot.create(:community)
    stranger = FactoryBot.create(:person, community_id: other_community.id)
    FactoryBot.create(:community_membership, person: stranger, community: other_community)
    other_token, = APIToken.issue!(person: stranger, name: "Other Shop Token", scopes: ["read"])

    admin_sign_in
    post "http://#{@domain}/ja/admin/users/api-tokens/#{other_token.id}/revoke"

    expect(response.status).to eq(404)
    expect(other_token.reload.revoked?).to eq(false)
  end

  it "管理者でなければ一覧も失効もできない" do
    post "http://#{@domain}/ja/admin/users/api-tokens/#{@token.id}/revoke"

    expect(response.status).to redirect_to(%r{/login})
    expect(@token.reload.revoked?).to eq(false)
  end
end
