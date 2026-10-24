# frozen_string_literal: true

require 'spec_helper'

# 設定画面ボタンの CSS フック契約（Issue #15 の回帰ガード）:
# ダークテーマ配色パッチ（app/assets/stylesheets/components/_raku_utils.scss）は
# 以下の id / class をセレクタにしており、ビュー側がこれらを描画し続けることが
# 前提になる。リネーム等で CSS が静かに当たらなくなる事故を検知する。
#
# - #email_submit / #password_submit / .send_button_account（account.haml）
# - .send_button_notifications（notifications.haml）
# - #delete_account_button（account.haml、破壊的ボタン）
# - .send_button（show.haml、既存パッチの回帰）
#
# 参考: 配色・コントラストの数値検証は scripts/theme_contrast_check.js で行う。
describe "Settings buttons (theme CSS hooks)", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "settings-theme.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload

    @person = FactoryBot.create(:person, username: "settingstheme",
                                         community_id: @community.id)
    FactoryBot.create(:community_membership, person: @person, community: @community)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  def sign_in
    token = UserService::API::AuthTokens.create_login_token(@person.id)[:token]
    get "http://#{@domain}/ja?auth=#{token}"
  end

  it "renders account settings save/delete buttons with the patched hooks" do
    sign_in
    get "http://#{@domain}/ja/#{@person.username}/settings/account"

    expect(response.status).to eq(200)
    expect(response.body).to include('id="email_submit"')
    expect(response.body).to include('id="password_submit"')
    expect(response.body).to include('id="delete_account_button"')
    expect(response.body).to include('class="send_button_account"')
  end

  it "renders notification settings save button with the patched hook" do
    sign_in
    get "http://#{@domain}/ja/#{@person.username}/settings/notifications"

    expect(response.status).to eq(200)
    expect(response.body).to include('class="send_button_notifications"')
  end

  it "renders profile settings save button used by the shared gold patch" do
    sign_in
    get "http://#{@domain}/ja/#{@person.username}/settings"

    expect(response.status).to eq(200)
    expect(response.body).to include('class="send_button"')
  end
end
