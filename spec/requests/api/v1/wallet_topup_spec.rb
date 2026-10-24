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
    # Issue #46: 固定額プリペイド (plan_id) のみ本番対応。任意額 amount_cents は
    # 非 dev で 422 plan_id_required（Freemius に任意額 checkout が無いため）。
    # Stripe 経路は Issue #43 で除去済み（Freemius 一本）。
    context "非 dev 環境では任意額チャージを受け付けない（固定額のみ）" do
      before { sign_in_as(person) }

      it "returns 422 with plan_id_required (Freemius 任意額は不可)" do
        post "/api/v1/wallet_topup", params: { amount_cents: 1000 }

        expect(response).to have_http_status(422)
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("plan_id_required")
      end

      it "does not create a wallet on arbitrary-amount rejection" do
        expect { post "/api/v1/wallet_topup", params: { amount_cents: 1000 } }
          .not_to change(Wallet, :count)
      end

      it "returns 422 when plan_id is missing entirely" do
        post "/api/v1/wallet_topup", params: {}
        expect(response).to have_http_status(422)
        expect(JSON.parse(response.body)["error_type"]).to eq("plan_id_required")
      end
    end

    context "固定額プリペイド (plan_id) の本番経路 (Issue #46)" do
      before { sign_in_as(person) }

      def stub_fixed_env(topup_map: { "5678" => 1000, "5679" => 3000 }, rate: "0.0067")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("FREEMIUS_PRODUCT_ID").and_return("1234")
        allow(ENV).to receive(:[]).with("API_BEARER_AUTHORIZATION_TOKEN").and_return("bearer")
        allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return(rate)
        allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_return(topup_map.to_json)
      end

      it "returns a hosted checkout URL for a known plan_id" do
        stub_fixed_env
        post "/api/v1/wallet_topup", params: { plan_id: "5678" }
        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json["checkout_url"]).to include("/product/1234/plan/5678/")
        expect(json["checkout_url"]).to include("cancel_url=")
        expect(json["cancel_url"]).to be_present
        expect(json["plan_id"]).to eq("5678")
        expect(json["credit_jpy"]).to eq(1000)
        expect(json["amount_cents"]).to eq(1000)
        expect(json["amount_usd_cents"]).to eq(670)
        expect(json["currency"]).to eq("usd")
        expect(json["provider"]).to eq("freemius")
      end

      it "ignores client amount_cents when plan_id is present (server decides)" do
        stub_fixed_env
        post "/api/v1/wallet_topup", params: { plan_id: "5678", amount_cents: 1 }
        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)["credit_jpy"]).to eq(1000)
      end

      it "returns 422 for an unknown plan_id" do
        stub_fixed_env
        post "/api/v1/wallet_topup", params: { plan_id: "nope" }
        expect(response).to have_http_status(422)
        expect(JSON.parse(response.body)["error_type"]).to eq("invalid_plan")
      end

      it "returns 503 when the FX rate is unconfigured (no silent default rate)" do
        stub_fixed_env(rate: nil)
        post "/api/v1/wallet_topup", params: { plan_id: "5678" }
        expect(response).to have_http_status(503)
        json = JSON.parse(response.body)
        expect(json["error_type"]).to eq("payment_unconfigured")
        expect(json["reason"]).to eq("fx_rate_unconfigured")
      end

      it "returns 503 when TOPUP_MAP is unconfigured" do
        stub_fixed_env(topup_map: {})
        allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_return(nil)
        post "/api/v1/wallet_topup", params: { plan_id: "5678" }
        # plan 未解決のため 422 invalid_plan（map 自体が無い場合は plan 解決不可）
        # または 503 topup_plans_unconfigured のいずれかで fail-closed。
        expect([422, 503]).to include(response.status)
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
    # 非 dev の任意額 POST は上記 422 例でカバーする（Issue #46）。
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

      context "Freemius のみ設定・レート未設定では wallet は無効のまま" do
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

      context "固定額プリペイドが設定済みの場合 (Issue #46)" do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("FREEMIUS_JPY_USD_RATE").and_return("0.0067")
          allow(ENV).to receive(:[]).with("FREEMIUS_TOPUP_PLAN_MAP").and_return({ "5678" => 1000, "5679" => 3000 }.to_json)
          allow(FreemiusClient).to receive(:configured?).and_return(true)
        end

        it "returns denominations with plan_id / USD / JPY" do
          get "/api/v1/wallet_topup/status"
          expect(response).to have_http_status(200)
          json = JSON.parse(response.body)
          expect(json["topup_enabled"]).to eq(true)
          expect(json["provider"]).to eq("freemius")
          expect(json["fx_rate"]).to eq(0.0067)
          denoms = json["denominations"]
          expect(denoms.map { |d| d["plan_id"] }).to eq(%w[5678 5679])
          expect(denoms.first["credit_jpy"]).to eq(1000)
          expect(denoms.first["estimated_usd_cents"]).to eq(670)
          expect(denoms.first["currency"]).to eq("usd")
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
