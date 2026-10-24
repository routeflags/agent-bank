# frozen_string_literal: true

require 'rails_helper'

# ChatPanel i18n props (lamprey.chat.* → React props.i18n) — DESIGN.md §13-15
describe "Chat panel i18n props", type: :request do
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  def listing_for(locales)
    domain = "chat-i18n-#{locales.join('-')}.custom.org"
    community = FactoryBot.create(:community, domain: domain, use_domain: true,
                                              settings: { "locales" => locales })
    author = FactoryBot.create(:person, username: "i18nauthor#{rand(10_000)}",
                                        community_id: community.id, member_of: community)
    listing = FactoryBot.create(:listing, community_id: community.id, author: author,
                                          default_run_mode: "run_online")
    [domain, listing]
  end

  it "renders Japanese chat strings on ja pages" do
    domain, listing = listing_for(%w[ja])
    get "http://#{domain}/ja/listings/#{listing.id}"
    expect(response.status).to eq(200)
    expect(response.body).to include('"input_placeholder":"メッセージを入力してください..."')
    expect(response.body).to include('"attach_button":"画像を添付"')
  end

  it "renders English chat strings on en pages" do
    domain, listing = listing_for(%w[en ja])
    get "http://#{domain}/en/listings/#{listing.id}"
    expect(response.status).to eq(200)
    expect(response.body).to include('"input_placeholder"')
    expect(response.body).to include("Type a message...")
    expect(response.body).to include("Attach image")
  end
end
