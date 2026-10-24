# frozen_string_literal: true

require 'rails_helper'

# Freemius hosted checkout success redirect (`GET /freemius/return`).
# Dashboard Plans → Customization → Redirect Checkout to a custom URL.
# Signature: HMAC-SHA256(clean_url, PRODUCT_SECRET_KEY).
RSpec.describe "FreemiusReturn", type: :request do
  let(:secret) { "test_return_secret" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PRODUCT_SECRET_KEY").and_return(secret)
    allow(ENV).to receive(:[]).with("FREEMIUS_WEBHOOK_SECRET").and_return(nil)
  end

  def get_return(pairs)
    query = URI.encode_www_form(pairs)
    clean = "http://www.example.com/freemius/return?#{query}"
    sig = OpenSSL::HMAC.hexdigest("SHA256", secret, clean)
    get "/freemius/return?#{query}&signature=#{sig}"
  end

  it "renders completion for a valid signature (generic, top-up only)" do
    get_return([["payment_id", "111"], ["plan_id", "74358"]])
    expect(response).to have_http_status(200)
    expect(response.body).to include(I18n.t("lamprey.freemius_return.success_title"))
  end

  it "renders Japanese when lang=ja is part of the signed URL" do
    pairs = [["lang", "ja"], ["payment_id", "111"], ["plan_id", "74358"]]
    query = URI.encode_www_form(pairs)
    clean = "http://www.example.com/freemius/return?#{query}"
    sig = OpenSSL::HMAC.hexdigest("SHA256", secret, clean)
    get "/freemius/return?#{query}&signature=#{sig}"
    expect(response).to have_http_status(200)
    expect(response.body).to include("購入が完了しました")
  end

  it "shows a warning (still 200) for an invalid signature" do
    get "/freemius/return?payment_id=111&plan_id=74358&signature=bad"
    expect(response).to have_http_status(200)
    expect(response.body).to include(I18n.t("lamprey.freemius_return.invalid_signature"))
  end

  it "shows a warning (still 200) when the signature is missing" do
    get "/freemius/return?payment_id=111&plan_id=74358"
    expect(response).to have_http_status(200)
    expect(response.body).to include(I18n.t("lamprey.freemius_return.invalid_signature"))
  end

  it "残高反映の遅延メモを常に表示する（Issue #58）" do
    get_return([["payment_id", "111"], ["plan_id", "74358"]])
    expect(response).to have_http_status(200)
    expect(response.body).to include(I18n.t("lamprey.freemius_return.wallet_delay_note"))
  end

  # マイページ導線（Issue #58）: ログイン中のみ本人ページへのリンクを出す。
  context "マイページへのリンク" do
    include Devise::Test::IntegrationHelpers

    let(:community) { FactoryBot.create(:community) }
    let(:person) { FactoryBot.create(:person, community_id: community.id) }

    it "ログイン中はマイページへ戻るリンクを表示する" do
      sign_in(person)
      get_return([["payment_id", "111"], ["plan_id", "74358"]])
      expect(response).to have_http_status(200)
      expect(response.body).to include(I18n.t("lamprey.freemius_return.back_to_mypage"))
      expect(response.body).to include(person.username)
    end

    it "未ログインではマイページへ戻るリンクを出さない（500にもしない）" do
      get_return([["payment_id", "111"], ["plan_id", "74358"]])
      expect(response).to have_http_status(200)
      expect(response.body).not_to include(I18n.t("lamprey.freemius_return.back_to_mypage"))
    end
  end
end
