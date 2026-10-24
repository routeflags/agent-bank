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
    # Stripe 経路は Issue #43 で除去した（Freemius 一本）。非 dev 環境では
    # 任意額チャージ自体が 503 になる。Stripe モック前提の例は意図的に削除。
    context "非 dev 環境では任意額チャージを提供しない（Stripe 不使用）" do
      before { sign_in_as(person) }

      it "returns 503 with payment_unconfigured (Freemius 任意額は不可)" do
        post "/api/v1/wallet_topup", params: { amount_cents: 1000 }

        expect(response).to have_http_status(503)
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("payment_unconfigured")
        expect(json["reason"]).to eq("freemius_arbitrary_amount_unsupported")
      end

      it "creates a wallet but does not credit (awaiting dev confirm only)" do
        expect { post "/api/v1/wallet_topup", params: { amount_cents: 1000 } }
          .to change(Wallet, :count).by(1)

        wallet = person.reload.wallet
        expect(wallet).to be_present
        expect(wallet.balance_cents).to eq(0)
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

      it "does not create any payment intent" do
        expect { post "/api/v1/wallet_topup", params: { amount_cents: 50 } }
          .not_to change(Wallet, :count)
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

    # Stripe エラー分岐は Issue #43 で除去（Freemius 一本）。Stripe モック例は廃止。
    # Freemius 任意額 checkout 分岐も廃止（Issue #43 で実現不可と確定）。
    # 非 dev の POST は上記 503 例でカバーする。
  end

  # ===================================================================
  # POST /api/v1/wallet_topup/confirm
  # ===================================================================
  describe "POST /api/v1/wallet_topup/confirm" do
    let(:wallet) {         FactoryBot.create(:wallet, person: person, community: community, balance_cents: 0) }

    # Stripe PaymentIntent 確定経路は Issue #43 で除去。非 dev の intent は
    # confirm_unsupported になる。dev 冪等は後段の開発環境ブロックで検証。
    context "非 dev の payment_intent では確定できない" do
      before { sign_in_as(person) }

      it "returns 422 with confirm_unsupported" do
        post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_test_success" }

        expect(response).to have_http_status(422)
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("confirm_unsupported")
      end

      it "does not credit the wallet" do
        expect {
          post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_test_success" }
        }.not_to change { wallet.reload.balance_cents }
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

    context "非 dev intent の他人の指定でも 422（Stripe 参照なし）" do
      before { sign_in_as(person) }

      it "returns 422" do
        post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "pi_other_user" }
        expect(response).to have_http_status(422)
      end
    end
  end

  # ===================================================================
  # GET /api/v1/wallet_topup/status（Issue #34）
  # ===================================================================
  describe "GET /api/v1/wallet_topup/status" do
    context "未認証の場合" do
      it "returns 401" do
        get "/api/v1/wallet_topup/status"
        expect(response).to have_http_status(401)
      end
    end

    context "認証済みの場合" do
      before { sign_in_as(person) }

      # Freemius 任意額は不可・Stripe 不使用のため、非 dev は常に無効（Issue #43）。
      context "決済手段が未設定の場合" do
        it "returns topup_enabled false with reason" do
          get "/api/v1/wallet_topup/status"
          expect(response).to have_http_status(200)
          json = JSON.parse(response.body)
          expect(json["topup_enabled"]).to eq(false)
          expect(json["provider"]).to be_nil
          expect(json["reason"]).to eq("payment_unconfigured")
        end
      end

      context "Freemius が設定されていても wallet は無効のまま（任意額不可）" do
        before do
          allow(FreemiusClient).to receive(:configured?).and_return(true)
        end

        it "returns topup_enabled false" do
          get "/api/v1/wallet_topup/status"
          expect(response).to have_http_status(200)
          json = JSON.parse(response.body)
          expect(json["topup_enabled"]).to eq(false)
          expect(json["provider"]).to be_nil
          expect(json["reason"]).to eq("payment_unconfigured")
        end
      end

      context "開発環境の擬似決済が有効な場合" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "returns topup_enabled true with dev_mode" do
          get "/api/v1/wallet_topup/status"
          expect(response).to have_http_status(200)
          json = JSON.parse(response.body)
          expect(json["topup_enabled"]).to eq(true)
          expect(json["dev_mode"]).to eq(true)
          expect(json["provider"]).to eq("dev")
        end
      end
    end
  end

  # ===================================================================
  # 開発環境の擬似決済（Issue #34: dev_mode_topup? 経路）
  # ===================================================================
  describe "開発環境の擬似決済" do
    before do
      sign_in_as(person)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
    end

    it "POST create は dev_pi_* の擬似 PaymentIntent を返す" do
      post "/api/v1/wallet_topup", params: { amount_cents: 3000 }
      expect(response).to have_http_status(200)
      json = JSON.parse(response.body)
      expect(json["payment_intent_id"]).to start_with("dev_pi_")
      expect(json["dev_mode"]).to eq(true)
      expect(json["amount_cents"]).to eq(3000)
    end

    it "POST confirm でウォレットにチャージされ二重確定は冪等" do
      post "/api/v1/wallet_topup", params: { amount_cents: 3000 }
      intent_id = JSON.parse(response.body)["payment_intent_id"]
      wallet = person.reload.wallet
      expect(wallet).to be_present

      expect { post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: intent_id } }
        .to change { wallet.reload.balance_cents }.by(3000)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("ok")
      expect(json["dev_mode"]).to eq(true)

      expect { post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: intent_id } }
        .not_to change { wallet.reload.balance_cents }
      json = JSON.parse(response.body)
      expect(json["amount_credited"]).to eq(0)
    end

    it "開発環境では Freemius 設定より擬似決済が優先される" do
      allow(FreemiusClient).to receive(:configured?).and_return(true)
      post "/api/v1/wallet_topup", params: { amount_cents: 1000 }
      json = JSON.parse(response.body)
      expect(json["dev_mode"]).to eq(true)
    end

    it "他人 uid の擬似 intent は 403" do
      wallet = FactoryBot.create(:wallet, person: person, community: community, balance_cents: 0)
      payload = { "uid" => "someone_else", "wid" => wallet.id, "amt" => 1000, "rnd" => "abcdef" }
      intent_id = "dev_pi_#{Base64.urlsafe_encode64(payload.to_json, padding: false)}"
      post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: intent_id }
      expect(response).to have_http_status(403)
    end

    it "不正な擬似 intent は 422" do
      post "/api/v1/wallet_topup/confirm", params: { payment_intent_id: "dev_pi_not-base64!!!" }
      expect(response).to have_http_status(422)
    end
  end
end
