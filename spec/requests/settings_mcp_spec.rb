# frozen_string_literal: true

require "spec_helper"

# 設定画面の「MCP 接続」（Issue #146）。
#
# 押さえたい契約:
# - 平文トークンは発行したリクエストのレスポンスにだけ出る（リロードの GET で
#   は出ない。flash / session に残さない）
# - 一覧には平文も digest も出ない
# - 発行したトークンで実際に API が使え、失効させたら使えなくなる
# - 他人のトークンは失効できない（404）
# - スコープ未選択の既定は read
RSpec.describe "設定の MCP 接続画面", type: :request do
  # test 環境は allow_forgery_protection=true のため、POST / DELETE は CSRF トークン
  # なしで拒否される。このファイルの example のみ無効化する。
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before(:all) do
    DatabaseCleaner.start

    @domain = "mcp-settings.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true,
                                               settings: { "locales" => ["ja"] })
    @community.reload

    @person = FactoryBot.create(:person, username: "mcpsettings", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)

    @other = FactoryBot.create(:person, username: "mcpother", community_id: @community.id)
    FactoryBot.create(:community_membership, person: @other, community: @community)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  # before(:all) のレコードはトランザクションでロールバックされないため、
  # トークンだけはサンプルごとに消す（実行順に依存しないように）。
  after(:each) do
    APIToken.delete_all
  end

  def sign_in_as(person)
    token = UserService::API::AuthTokens.create_login_token(person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  def mcp_page_url(person = @person)
    "http://#{@domain}/ja/#{person.username}/settings/mcp"
  end

  def issue_token_page(params)
    post "http://#{@domain}/ja/#{@person.username}/settings/mcp_token", params: params
  end

  def revoke_url(token_id, person = @person)
    "http://#{@domain}/ja/#{person.username}/settings/mcp_token?token_id=#{token_id}"
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def personas_api(token)
    get "http://#{@domain}/api/v1/personas", headers: { "Authorization" => "Bearer #{token}" }
  end

  # 画面に出ている平文トークン（発行直後のみ存在する）。
  def shown_raw_token
    page.at_css("#mcp-raw-token")&.text&.strip
  end

  # 直前に発行されたトークン。before(:all) の @person を使い回すと関連
  # キャッシュが古いままになりうるため、毎回引き直す。
  def latest_token
    APIToken.where(person_id: @person.id).order(:id).last
  end

  describe "未ログイン" do
    it "302 でログインへ送る" do
      get mcp_page_url

      expect(response).to have_http_status(:found)
      expect(response.location).to include("/login")
    end
  end

  describe "一覧" do
    it "平文も digest も出ない" do
      token, raw_token = APIToken.issue!(person: @person, name: "一覧のトークン", scopes: ["read"])
      sign_in_as(@person)

      get mcp_page_url

      expect(response).to have_http_status(200)
      expect(response.body).to include("一覧のトークン")
      expect(response.body).not_to include(raw_token)
      expect(response.body).not_to include(token.token_digest)
      expect(page.at_css("#mcp-raw-token")).to be_nil
    end
  end

  describe "発行" do
    before { sign_in_as(@person) }

    it "平文トークンと設定スニペットを一度だけ表示する" do
      issue_token_page(name: "Claude Desktop", scopes: ["read", "run"])

      expect(response).to have_http_status(200)
      raw_token = shown_raw_token
      expect(raw_token).to be_present

      # 平文は DB に残らない（digest だけ）
      token = latest_token
      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))

      snippet = JSON.parse(page.at_css("#mcp-config-snippet").text)
      server = snippet.fetch("mcpServers").fetch("agentbank")
      expect(server["command"]).to eq("npx")
      expect(server["args"]).to eq(["-y", "@agentbank/mcp"])
      # スニペットにはいま発行した平文トークンが入る
      expect(server.dig("env", "AGENTBANK_TOKEN")).to eq(raw_token)
      expect(server.dig("env", "AGENTBANK_BASE_URL")).to eq("http://#{@domain}")

      # リロード（同一 URL の GET）では平文が消える
      get mcp_page_url
      expect(response).to have_http_status(200)
      expect(response.body).not_to include(raw_token)
      expect(page.at_css("#mcp-raw-token")).to be_nil
    end

    it "スコープ未選択なら read だけが付く" do
      issue_token_page(name: "既定スコープ")

      expect(response).to have_http_status(200)
      expect(latest_token.scope_list).to eq(["read"])
    end

    it "名前が空なら 422 でエラーを出す" do
      issue_token_page(name: "  ")

      expect(response).to have_http_status(422)
      expect(page.at_css("[role=alert]").text).to include("名前を入力してください")
      expect(APIToken.where(person_id: @person.id).count).to eq(0)
      expect(shown_raw_token).to be_nil
    end
  end

  describe "発行したトークンで API を使う" do
    before { sign_in_as(@person) }

    it "Authorization: Bearer でペルソナ API が 200 になる" do
      issue_token_page(name: "API 用", scopes: ["read"])
      raw_token = shown_raw_token

      personas_api(raw_token)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to have_key("personas")
    end
  end

  describe "失効" do
    before { sign_in_as(@person) }

    it "失効させると一覧の状態が変わり、そのトークンでは API が 401 になる" do
      issue_token_page(name: "失効させる", scopes: ["read"])
      raw_token = shown_raw_token
      token = latest_token

      delete revoke_url(token.id)

      expect(response).to have_http_status(:found)
      expect(token.reload.revoked?).to be true

      personas_api(raw_token)
      expect(response).to have_http_status(401)

      get mcp_page_url
      status_cell = page.css("table.raku-table tbody tr").first.css("td")[4].text.strip
      expect(status_cell).to eq("失効")
    end

    it "他人のトークン ID は 404（失効させない）" do
      others_token, = APIToken.issue!(person: @other, name: "他人のトークン", scopes: ["read"])

      delete revoke_url(others_token.id)

      expect(response).to have_http_status(404)
      expect(others_token.reload.revoked?).to be false
    end
  end

  describe "タブ" do
    it "設定画面の左ナビに「MCP 接続」が出る" do
      sign_in_as(@person)

      get "http://#{@domain}/ja/#{@person.username}/settings"

      tab = page.at_css("#settings-tab-mcp")
      expect(tab).to be_present
      expect(tab["href"]).to eq("/ja/#{@person.username}/settings/mcp")
    end
  end

  describe "短縮 URL" do
    it "GET /settings/mcp は本人の画面へリダイレクトする" do
      sign_in_as(@person)

      get "http://#{@domain}/ja/settings/mcp"

      expect(response).to have_http_status(:found)
      expect(response.location).to include("/ja/#{@person.username}/settings/mcp")
    end
  end
end
