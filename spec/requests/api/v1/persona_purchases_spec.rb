# frozen_string_literal: true

require 'rails_helper'

# 本番購入導線（Freemius ホスト型 Checkout URL）API のスペック。
# POST /api/v1/persona_purchases
#
# 実 Freemius API には一切接続しない（FreemiusClient はすべてスタブ）。
# hosted checkout は plan 単位で、サーバーは URL を組み立てるのみ。
# 金額・購入者がサーバー側で決まることを固定する。
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

      it "503 と error_type: purchase_not_configured を返し、URL を作らない" do
        allow(FreemiusClient).to receive(:configured?).and_return(false)
        allow(FreemiusClient).to receive(:build_hosted_checkout_url)

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(503)
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("purchase_not_configured")
        expect(FreemiusClient).not_to have_received(:build_hosted_checkout_url)
      end

      it "plan 未解決でも 503 purchase_not_configured（500 にしない）" do
        allow(FreemiusClient).to receive(:configured?).and_return(true)
        allow(FreemiusClient).to receive(:plan_id_for_listing).and_return(nil)
        allow(FreemiusClient).to receive(:build_hosted_checkout_url)

        post_purchase

        expect(response).to have_http_status(503)
        expect(JSON.parse(response.body)["error_type"]).to eq("purchase_not_configured")
        expect(FreemiusClient).not_to have_received(:build_hosted_checkout_url)
      end
    end

    context "Freemius 設定済みの場合" do
      before do
        sign_in(person)
        allow(FreemiusClient).to receive(:configured?).and_return(true)
        allow(FreemiusClient).to receive(:plan_id_for_listing).and_return("5678")
        # 換算レートは実ロジックで検証する（0.0067 固定）。plan 価格 map は
        # 未設定のため check_plan_price は :unknown（warn なし・200 継続）。
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return("0.0067")
      end

      def stub_hosted_url(url = "https://checkout.freemius.com/product/1234/plan/5678/")
        allow(FreemiusClient).to receive(:build_hosted_checkout_url).and_return(url)
      end

      it "hosted checkout_url を返し、plan 解決に listing を使う" do
        stub_hosted_url

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json["checkout_url"]).to start_with("https://checkout.freemius.com/product/")
        expect(json["plan_id"]).to eq("5678")
        expect(json["listing_id"]).to eq(listing.id)
        expect(json["provider"]).to eq("freemius")
        expect(json["amount_cents"]).to eq(3000)
        # JPY→USD 換算値（既存 field は維持しつつ追加）
        expect(json["amount_jpy"]).to eq(3000)
        expect(json["amount_usd_cents"]).to eq(2010)
        expect(json["currency"]).to eq("usd")
        expect(json["fx_rate"]).to eq(0.0067)

        expect(FreemiusClient).to have_received(:plan_id_for_listing) do |arg|
          expect(arg.id).to eq(listing.id)
        end
      end

      it "残高ゼロでも購入できる（残高に依存しない・Issue #46）" do
        stub_hosted_url
        FactoryBot.create(:wallet, person: person, community: community, balance_cents: 0)
        expect(person.reload.wallet.balance_cents).to eq(0)

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)["checkout_url"]).to start_with("https://checkout.freemius.com/product/")
      end

      it "クライアントが渡した価格・ユーザーは無視される（listing_id のみ信じる）" do
        stub_hosted_url

        post_purchase(listing.id, { amount_cents: 1, user_id: author.id, currency: "USD" })

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json["amount_cents"]).to eq(3000)
        expect(json["listing_id"]).to eq(listing.id)
      end

      it "存在しないペルソナは 404" do
        stub_hosted_url

        post_purchase(-1)

        expect(response).to have_http_status(404)
        expect(JSON.parse(response.body)["error_type"]).to eq("listing_not_found")
        expect(FreemiusClient).not_to have_received(:build_hosted_checkout_url)
      end

      it "無料ペルソナは 422（Checkout を作らない）" do
        free_listing = FactoryBot.create(:listing, community_id: community.id, author: author)
        free_listing.update!(price_cents: 0)
        stub_hosted_url

        post_purchase(free_listing.id)

        expect(response).to have_http_status(422)
        expect(JSON.parse(response.body)["error_type"]).to eq("free_listing")
        expect(FreemiusClient).not_to have_received(:build_hosted_checkout_url)
      end

      it "既に購入済みなら Checkout を作らず already_purchased を返す" do
        stub_hosted_url
        UserPlanSubscriptionService.create_for(
          person: person, listing: listing, payment_reference: "spec_seed"
        )

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("already_purchased")
        expect(FreemiusClient).not_to have_received(:build_hosted_checkout_url)
      end

      it "換算レート未設定なら 503 payment_unconfigured（checkout を作らない）" do
        allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return(nil)
        allow(FreemiusClient).to receive(:build_hosted_checkout_url)

        expect { post_purchase }.not_to change(UserPlanSubscription, :count)

        expect(response).to have_http_status(503)
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("payment_unconfigured")
        expect(json["reason"]).to eq("fx_rate_unconfigured")
        expect(FreemiusClient).not_to have_received(:build_hosted_checkout_url)
      end

      it "plan 価格と乖離しても warn に留め 200 を返す（遮断しない）" do
        stub_hosted_url
        allow(ENV).to receive(:[]).with("FREEMIUS_PLAN_PRICE_MAP")
          .and_return({ "5678" => 999 }.to_json)
        allow(Rails.logger).to receive(:warn)

        post_purchase

        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)["amount_usd_cents"]).to eq(2010)
        expect(Rails.logger).to have_received(:warn).with(/plan price drift/)
      end

      it "URL 組み立て失敗は 502 と error_type: checkout_failed" do
        allow(FreemiusClient).to receive(:build_hosted_checkout_url)
          .and_raise(FreemiusClient::ApiError.new("upstream error"))

        post_purchase

        expect(response).to have_http_status(502)
        expect(JSON.parse(response.body)["error_type"]).to eq("checkout_failed")
      end
    end
  end
end
