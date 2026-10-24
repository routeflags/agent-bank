# frozen_string_literal: true

require 'rails_helper'

# 開発/テスト専用の購入付与 API のスペック。
# POST /api/v1/dev/persona_purchases
#
# 「購入 → チャット利用」を実課金なしで検証するための経路。
# 本番に購入偽装の経路を残さないため、フラグが無い限り 404 で存在を隠す。
RSpec.describe "Api::V1::Dev::PersonaPurchases", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:other_person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: other_person) }

  def with_dev_flag(value)
    original = ENV[DevPersonaPurchase::ENABLE_FLAG]
    ENV[DevPersonaPurchase::ENABLE_FLAG] = value
    yield
  ensure
    ENV[DevPersonaPurchase::ENABLE_FLAG] = original
  end

  def post_purchase(listing_id = listing.id)
    post "/api/v1/dev/persona_purchases", params: { listing_id: listing_id }
  end

  describe "POST /api/v1/dev/persona_purchases" do
    context "未認証の場合" do
      it "401 を返し、購入権利も作成しない" do
        with_dev_flag("true") do
          expect { post_purchase }.not_to change(UserPlanSubscription, :count)
        end

        expect(response).to have_http_status(401)
        expect(JSON.parse(response.body)["error"]).to eq("ログインが必要です")
      end
    end

    context "開発購入が無効な場合（既定）" do
      before { sign_in(person) }

      it "認証済みでも 404（エンドポイントの存在を隠す）" do
        with_dev_flag(nil) do
          expect { post_purchase }.not_to change(UserPlanSubscription, :count)
        end

        expect(response).to have_http_status(404)
      end

      it "production 環境ではフラグが true でも 404" do
        allow(Rails).to receive(:env)
          .and_return(ActiveSupport::EnvironmentInquirer.new("production"))

        with_dev_flag("true") do
          expect { post_purchase }.not_to change(UserPlanSubscription, :count)
        end

        expect(response).to have_http_status(404)
      end
    end

    context "開発購入が有効な場合" do
      before { sign_in(person) }

      it "存在しないペルソナは 404" do
        with_dev_flag("true") do
          expect { post_purchase(-1) }.not_to change(UserPlanSubscription, :count)
        end

        expect(response).to have_http_status(404)
        expect(JSON.parse(response.body)["error"]).to eq("ペルソナが見つかりません")
      end

      it "購入権利を作成し 201 を返す" do
        with_dev_flag("true") do
          expect { post_purchase }.to change(UserPlanSubscription, :count).by(1)
        end

        expect(response).to have_http_status(201)
        json = JSON.parse(response.body)["persona_purchase"]
        expect(json["listing_id"]).to eq(listing.id)
        expect(json["person_id"]).to eq(person.id)
        expect(json["status"]).to eq("active")
        expect(json["duplicate"]).to be false
      end

      it "購入後にチャットセッションを作成できる（購入 → チャットの一連の流れ）" do
        with_dev_flag("true") do
          post_purchase
        end
        expect(response).to have_http_status(201)

        expect {
          post "/api/v1/chat_sessions", params: { listing_id: listing.id }
        }.to change(ChatSession, :count).by(1)

        expect(response).to have_http_status(201)
        json = JSON.parse(response.body)["chat_session"]
        expect(json["listing_id"]).to eq(listing.id)
        # 購入（subscription）があるので billing_model は subscription 由来になる
        expect(json["billing_model"]).to eq("token_based")
      end

      it "既に購入済みなら 200 で既存の購入権利を返す" do
        with_dev_flag("true") do
          post_purchase
        end

        with_dev_flag("true") do
          expect { post_purchase }.not_to change(UserPlanSubscription, :count)
        end

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)["persona_purchase"]
        expect(json["duplicate"]).to be true
      end

      it "初回トークンがウォレットに付与される" do
        with_dev_flag("true") do
          post_purchase
        end

        expect(person.reload.wallet.balance_cents).to be > 0
      end
    end
  end
end
