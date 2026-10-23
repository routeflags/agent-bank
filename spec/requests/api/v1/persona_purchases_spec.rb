# frozen_string_literal: true

require 'rails_helper'

# 本番購入導線（Freemius Checkout 作成）API のスペック。
# POST /api/v1/persona_purchases
#
# 実 Freemius API には一切接続しない（FreemiusClient はすべてスタブ）。
# 金額・通貨・購入者がサーバー側で決まることを固定する。
RSpec.describe "Api::V1::PersonaPurchases", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id, author: author).tap do |l|
      l.update!(price_cents: 3000, currency: "JPY")
    end
  end

  def post_purchase(listing_id = listing.id, extra = {})
    post "/api/v1/persona_purchases", params: { listing_id: listing_id }.merge(extra)
  end

  describe "POST /api/v1/persona_purchases" do
    context "未認証の場合" do
      it "401 を返す" do
        allow(FreemiusClient).to receive(:configured?).and_return(false)

        post_purchase

        expect(response).to have_http_status(401)
        expect(JSON.parse(response.body)["error"]).to eq("ログインが必要です")
      end
    end

    context "Freemius 未設定の場合" do
      before { sign_in(person) }

      it "503 と error_type: purchase_not_configured を返し、Checkout を作らない" do
        allow(FreemiusClient).to receive(:configured?).and_return(false)
        allow(FreemiusClient).to receive(:create_persona_purchase_checkout)

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(503)
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("purchase_not_configured")
        expect(FreemiusClient).not_to have_received(:create_persona_purchase_checkout)
      end
    end

    context "Freemius 設定済みの場合" do
      before do
        sign_in(person)
        allow(FreemiusClient).to receive(:configured?).and_return(true)
      end

      def stub_checkout(payment_id: "fs_pay_1")
        allow(FreemiusClient).to receive(:create_persona_purchase_checkout)
          .and_return({ "checkout_url" => "https://checkout.freemius.test/c/abc",
                        "payment_id" => payment_id })
      end

      it "checkout_url を返し、サーバー側の値で Checkout を作成する" do
        stub_checkout

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json["checkout_url"]).to eq("https://checkout.freemius.test/c/abc")
        expect(json["payment_id"]).to eq("fs_pay_1")
        expect(json["provider"]).to eq("freemius")
        expect(json["amount_cents"]).to eq(3000)

        expect(FreemiusClient).to have_received(:create_persona_purchase_checkout).with(
          amount_cents: 3000,
          currency: "JPY",
          user_id: person.id,
          listing_id: listing.id
        )
      end

      it "クライアントが渡した価格・ユーザーは無視される（listing_id のみ信じる）" do
        stub_checkout

        post_purchase(listing.id, { amount_cents: 1, user_id: author.id, currency: "USD" })

        expect(response).to have_http_status(200)
        expect(FreemiusClient).to have_received(:create_persona_purchase_checkout).with(
          amount_cents: 3000,
          currency: "JPY",
          user_id: person.id,
          listing_id: listing.id
        )
      end

      it "存在しないペルソナは 404" do
        stub_checkout

        post_purchase(-1)

        expect(response).to have_http_status(404)
        expect(JSON.parse(response.body)["error_type"]).to eq("listing_not_found")
        expect(FreemiusClient).not_to have_received(:create_persona_purchase_checkout)
      end

      it "無料ペルソナは 422（Checkout を作らない）" do
        free_listing = FactoryBot.create(:listing, community_id: community.id, author: author)
        free_listing.update!(price_cents: 0)
        stub_checkout

        post_purchase(free_listing.id)

        expect(response).to have_http_status(422)
        expect(JSON.parse(response.body)["error_type"]).to eq("free_listing")
        expect(FreemiusClient).not_to have_received(:create_persona_purchase_checkout)
      end

      it "既に購入済みなら Checkout を作らず already_purchased を返す" do
        stub_checkout
        UserPlanSubscriptionService.create_for(
          person: person, listing: listing, payment_reference: "spec_seed"
        )

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("already_purchased")
        expect(FreemiusClient).not_to have_received(:create_persona_purchase_checkout)
      end

      it "Freemius API がエラーのときは 502 と error_type: checkout_failed" do
        allow(FreemiusClient).to receive(:create_persona_purchase_checkout)
          .and_raise(FreemiusClient::ApiError.new("upstream error"))

        post_purchase

        expect(response).to have_http_status(502)
        expect(JSON.parse(response.body)["error_type"]).to eq("checkout_failed")
      end

      it "checkout_url が無いレスポンスは 502 として扱う" do
        allow(FreemiusClient).to receive(:create_persona_purchase_checkout)
          .and_return({ "payment_id" => "fs_pay_2" })

        post_purchase

        expect(response).to have_http_status(502)
        expect(JSON.parse(response.body)["error_type"]).to eq("checkout_failed")
      end
    end
  end
end
