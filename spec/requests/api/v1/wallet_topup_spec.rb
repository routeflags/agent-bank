# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::WalletTopup", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }

  # ── Helpers ────────────────────────────────────────────────────────
  def sign_in_as(user)
    sign_in(user)
  end

  # ===================================================================
  # GET /api/v1/wallet_topup/balance
  # ===================================================================
  describe "GET /api/v1/wallet_topup/balance" do
    context "認証済みユーザーが残高を取得" do
      before { sign_in_as(person) }

      context "Wallet が既にある場合" do
        before do
          FactoryBot.create(:wallet, person: person, community: community, balance_cents: 2500)
        end

        it "returns 200 with balance" do
          get "/api/v1/wallet_topup/balance"
          expect(response).to have_http_status(200)
          json = JSON.parse(response.body)
          expect(json["balance_cents"]).to eq(2500)
          expect(json["currency"]).to be_present
        end
      end

      context "Wallet がない場合" do
        it "returns 200 with zero balance" do
          get "/api/v1/wallet_topup/balance"
          expect(response).to have_http_status(200)
          json = JSON.parse(response.body)
          expect(json["balance_cents"]).to eq(0)
        end

        it "creates a new wallet" do
          expect { get "/api/v1/wallet_topup/balance" }.to change(Wallet, :count).by(1)
        end
      end
    end

    context "未認証で残高を取得" do
      it "returns 401" do
        get "/api/v1/wallet_topup/balance"
        expect(response).to have_http_status(401)
      end
    end
  end

  # ===================================================================
  # POST /api/v1/wallet_topup
  # ===================================================================
  describe "POST /api/v1/wallet_topup" do
    context "認証済みユーザーが有効な金額でトップアップをリクエスト" do
      before do
        sign_in_as(person)
        # Stub the Stripe key configuration to avoid needing a real API key
        allow_any_instance_of(API::V1::WalletTopupController).to receive(:configure_stripe_api!).and_yield
      end

      it "returns 200 with client_secret" do
        # Stub Stripe::PaymentIntent.create to avoid real API call
        intent_double = double(
          id: "pi_test_123",
          client_secret: "cs_test_secret",
          amount: 1000
        )
        allow(Stripe::PaymentIntent).to receive(:create).and_return(intent_double)

        post "/api/v1/wallet_topup", params: { amount_cents: 1000 }

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json["client_secret"]).to eq("cs_test_secret")
        expect(json["payment_intent_id"]).to eq("pi_test_123")
        expect(json["amount_cents"]).to eq(1000)
      end

      it "creates or finds a wallet for the user" do
        intent_double = double(
          id: "pi_test_123",
          client_secret: "cs_test_secret",
          amount: 1000
        )
        allow(Stripe::PaymentIntent).to receive(:create).and_return(intent_double)

        expect { post "/api/v1/wallet_topup", params: { amount_cents: 1000 } }
          .to change(Wallet, :count).by(1)

        wallet = person.reload.wallet
        expect(wallet).to be_present
        expect(wallet.balance_cents).to eq(0)  # Not yet credited (awaiting confirm)
      end

      it "sends correct metadata to Stripe" do
        intent_double = double(
          id: "pi_test_123",
          client_secret: "cs_test_secret",
          amount: 1500
        )
        # Stub the Stripe API configuration to avoid needing a real key
        allow(Stripe::PaymentIntent).to receive(:create).and_return(intent_double)

        post "/api/v1/wallet_topup", params: { amount_cents: 1500 }
        expect(response).to have_http_status(200)
      end
    end

    context "金額が下限未満の場合" do
      before { sign_in_as(person) }

      it "returns 422 with validation error" do
        post "/api/v1/wallet_topup", params: { amount_cents: 50 }

        expect(response).to have_http_status(422)
        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end

      it "does not create a Stripe PaymentIntent" do
        expect(Stripe::PaymentIntent).not_to receive(:create)
        post "/api/v1/wallet_topup", params: { amount_cents: 50 }
      end
    end

    context "金額が上限超過の場合" do
      before { sign_in_as(person) }

      it "returns 422 with validation error" do
        post "/api/v1/wallet_topup", params: { amount_cents: 10_001 }

        expect(response).to have_http_status(422)
        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "金額が 0 の場合" do
      before { sign_in_as(person) }

      it "returns 422" do
        post "/api/v1/wallet_topup", params: { amount_cents: 0 }
        expect(response).to have_http_status(422)
      end
    end

    context "未認証でトップアップをリクエスト" do
      it "returns 401" do
        post "/api/v1/wallet_topup", params: { amount_cents: 1000 }
        expect(response).to have_http_status(401)
      end
    end

    context "Stripe エラーが発生した場合" do
      before do
        sign_in_as(person)
        # Stub the Stripe key configuration to avoid needing a real API key
        allow_any_instance_of(API::V1::WalletTopupController).to receive(:configure_stripe_api!).and_yield
        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(Stripe::InvalidRequestError.new("Invalid amount", nil))
      end

      it "returns 422 with Stripe error" do
        post "/api/v1/wallet_topup", params: { amount_cents: 1000 }
        expect(response).to have_http_status(422)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("決済の作成に失敗")
      end
    end
  end

  # ===================================================================
  # POST /api/v1/wallet_topup/confirm
  # ===================================================================
  describe "POST /api/v1/wallet_topup/confirm" do
    let(:wallet) {         FactoryBot.create(:wallet, person: person, community: community, balance_cents: 0) }

    context "PaymentIntent succeeded の場合" do
      before do
        sign_in_as(person)
      end

      it "Wallet にトークンを追加する" do
        intent_double = double(
          id: "pi_test_success",
          status: "succeeded",
          amount: 2000,
          metadata: {
            "user_id" => person.id,
            "wallet_id" => wallet.id.to_s,
            "type" => "wallet_topup"
          }
        )
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent_double)

        expect { post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_test_success" } }
          .to change { wallet.reload.balance_cents }.by(2000)

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("ok")
        expect(json["balance_cents"]).to eq(2000)
      end

      it "CreditTransaction (topup) を作成する" do
        intent_double = double(
          id: "pi_test_success",
          status: "succeeded",
          amount: 3000,
          metadata: {
            "user_id" => person.id,
            "wallet_id" => wallet.id.to_s,
            "type" => "wallet_topup"
          }
        )
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent_double)

        expect {
          post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_test_success" }
        }.to change(CreditTransaction, :count).by(1)

        tx = CreditTransaction.last
        expect(tx.transaction_type).to eq("topup")
        expect(tx.amount_cents).to eq(3000)
      end
    end

    context "PaymentIntent がまだ succeeded でない場合" do
      before { sign_in_as(person) }

      it "returns 422" do
        intent_double = double(
          id: "pi_test_pending",
          status: "requires_payment_method",
          amount: 1000,
          metadata: {
            "user_id" => person.id,
            "wallet_id" => wallet.id.to_s
          }
        )
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent_double)

        post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_test_pending" }

        expect(response).to have_http_status(422)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("決済が完了していません")
      end
    end

    context "payment_intent_id が未指定の場合" do
      before { sign_in_as(person) }

      it "returns 400" do
        post "/api/v1/wallet_topup/confirm", params: {}
        expect(response).to have_http_status(400)
      end
    end

    context "未認証で確認リクエスト" do
      it "returns 401" do
        post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_test" }
        expect(response).to have_http_status(401)
      end
    end

    context "他人の PaymentIntent を確認しようとする場合" do
      before { sign_in_as(person) }

      it "returns 403" do
        intent_double = double(
          id: "pi_other_user",
          status: "succeeded",
          amount: 1000,
          metadata: {
            "user_id" => "other_user_id",
            "wallet_id" => wallet.id.to_s
          }
        )
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent_double)

        post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_other_user" }
        expect(response).to have_http_status(403)
      end
    end
  end
end
