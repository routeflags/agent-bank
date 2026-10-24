# frozen_string_literal: true

require 'spec_helper'

# Issue #21: レガシーページ（React アプリを提供しないページ）が、webpack の
# 分割ビルドで実際に生成される CSS だけを参照することを確認する回帰テスト。
#
# 前提: `app/assets/webpack` にビルド済みアセットがあること（他ページを描画
# するリクエストスペックと同じ前提）。
RSpec.describe "Legacy page assets", type: :request do
  let(:domain) { "legacy-assets.custom.org" }

  before do
    @community = FactoryBot.create(:community, domain: domain, use_domain: true)
    @community.reload
  end

  it "loads sections-bundle.css and not the no longer generated app-bundle.css" do
    get "https://#{domain}/login"

    expect(response.status).to eq(200)
    expect(response.body).to include("sections-bundle")
    expect(response.body).not_to include("app-bundle")
  end
end
