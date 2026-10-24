# frozen_string_literal: true

require 'spec_helper'

# 情報系静的ページ（infos）の描画ガード
describe "Infos pages", type: :request do
  before(:all) do
    DatabaseCleaner.start

    @domain = "infos-pages.custom.org"
    @community = FactoryBot.create(:community, domain: @domain, use_domain: true, settings: { "locales" => ["ja"] })
    @community.reload
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  {
    "about" => "/ja/infos/about",
    "how_to_use" => "/ja/infos/how_to_use",
    "terms" => "/ja/infos/terms",
    "privacy" => "/ja/infos/privacy"
  }.each do |name, path|
    it "renders infos##{name}" do
      get "http://#{@domain}#{path}"

      expect(response.status).to eq(200)
    end
  end
end
