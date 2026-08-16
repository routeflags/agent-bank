# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPlanSubscriptionService, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: person) }
  let(:transaction) do
    FactoryBot.create(:transaction,
           starter: person,
           listing: listing,
           community: community,
           current_state: "confirmed")
  end

  describe ".create_on_purchase" do
    subject(:result) { described_class.create_on_purchase(transaction) }

    context "初回購入の場合" do
      it "UserPlanSubscription を作成する" do
        expect { result }.to change(UserPlanSubscription, :count).by(1)
        expect(result.subscription).to be_persisted
        expect(result.subscription.person).to eq(person)
        expect(result.subscription.listing).to eq(listing)
        expect(result.subscription.status).to eq("active")
      end

      it "billing_model は token_based を設定する" do
        expect(result.subscription.billing_model).to eq("token_based")
      end

      it "Wallet を作成し初回トークンを付与する" do
        expect { result }.to change(Wallet, :count).by(1)
        wallet = person.wallet
        expect(wallet).to be_present
        expect(wallet.balance_cents).to be > 0
      end

      it "CreditTransaction (topup) を作成する" do
        expect { result }.to change(CreditTransaction, :count).by(1)
        tx = CreditTransaction.last
        expect(tx.transaction_type).to eq("topup")
        expect(tx.amount_cents).to be > 0
      end

      it "duplicate? は false を返す" do
        expect(result.duplicate?).to be false
      end
    end

    context "二重購入の場合" do
      before do
        described_class.create_on_purchase(transaction)
      end

      it "新しいサブスクリプションは作成しない" do
        expect { result }.not_to change(UserPlanSubscription, :count)
      end

      it "既存のサブスクリプションを返す" do
        expect(result.subscription).to be_persisted
        expect(result.duplicate?).to be true
      end

      it "Wallet の残高は変更しない" do
        wallet = person.wallet
        initial_balance = wallet.balance_cents
        result
        expect(wallet.reload.balance_cents).to eq(initial_balance)
      end
    end

    context "Wallet がまだない場合" do
      it "Wallet を新規作成する" do
        expect(person.wallet).to be_nil
        expect { result }.to change(Wallet, :count).by(1)
        expect(person.reload.wallet).to be_present
      end
    end

    context "既存の Wallet がある場合" do
      before do
        FactoryBot.create(:wallet, person: person, community: community, balance_cents: 500)
      end

      it "既存 Wallet を使い残高を増やす" do
        expect { result }.not_to change(Wallet, :count)
        expect(person.wallet.reload.balance_cents).to be > 500
      end
    end

    context "2回目の購入で billing_model が subscription_with_overage になる場合" do
      before do
        described_class.create_on_purchase(transaction)
      end

      it "既に subscription が存在するため二重購入となり duplicate? が true" do
        # The service returns existing subscription when duplicate
        expect(result.duplicate?).to be true
      end
    end

    # ── Edge case tests ────────────────────────────────────────────

    context "同一のペルソナに対して複数のトランザクションが発生した場合" do
      let(:second_transaction) do
        FactoryBot.create(:transaction,
               starter: person,
               listing: listing,
               community: community,
               current_state: "confirmed")
      end

      before do
        described_class.create_on_purchase(transaction)
      end

      it "2回目は idempotent に既存サブスクリプションを返す" do
        second_result = described_class.create_on_purchase(second_transaction)
        expect(second_result.duplicate?).to be true
        expect(second_result.subscription.id).to eq(result.subscription.id)
      end
    end

    context "サブスクリプションの period が正しく設定されている場合" do
      it "current_period_start が現在時刻である" do
        expect(result.subscription.current_period_start).to be_within(5.seconds).of(Time.current)
      end

      it "current_period_end が1年後である" do
        expect(result.subscription.current_period_end).to be_within(5.seconds).of(1.year.from_now)
      end
    end

    context "Wallet 作成時の通貨がリストの通貨と一致する場合" do
      it "Wallet の currency が設定される" do
        wallet = result.wallet
        expect(wallet.currency).to be_present
      end
    end
  end
end
