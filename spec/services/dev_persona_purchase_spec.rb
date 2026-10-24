# frozen_string_literal: true

require 'rails_helper'

# 開発/テスト専用の購入付与ゲートと付与処理のスペック。
#
# 本番に購入偽装の経路を残さないことが最優先の要件なので、
#   * production ではフラグ値によらず無効
#   * development / test でもフラグが真のときのみ有効
# を明示的に検証する。
RSpec.describe DevPersonaPurchase, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: person) }

  # 環境フラグを差し替えてブロックを実行する（テスト後に必ず元に戻す）
  def with_env_flag(value)
    original = ENV[described_class::ENABLE_FLAG]
    ENV[described_class::ENABLE_FLAG] = value
    yield
  ensure
    ENV[described_class::ENABLE_FLAG] = original
  end

  def in_production
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    yield
  end

  describe ".enabled?" do
    context "LAMPREY_ENABLE_DEV_PURCHASE が true の場合" do
      it "development / test では有効" do
        with_env_flag("true") do
          expect(described_class.enabled?).to be true
        end
      end
    end

    context "環境フラグが無効な場合" do
      it "未設定なら無効（既定は無効）" do
        with_env_flag(nil) do
          expect(described_class.enabled?).to be false
        end
      end

      it "false / 0 / 空文字なら無効" do
        ["false", "0", ""].each do |value|
          with_env_flag(value) do
            expect(described_class.enabled?).to be(false), "value=#{value.inspect}"
          end
        end
      end
    end

    context "production 環境の場合" do
      it "フラグが true でも常に無効" do
        in_production do
          with_env_flag("true") do
            expect(described_class.enabled?).to be false
          end
        end
      end
    end
  end

  describe ".grant!" do
    context "ゲートが有効な場合" do
      it "購入権利と初回トークンを付与する" do
        with_env_flag("true") do
          result = nil
          expect {
            result = described_class.grant!(person: person, listing: listing)
          }.to change(UserPlanSubscription, :count).by(1)

          expect(result.duplicate?).to be false
          expect(result.subscription.status).to eq("active")
          expect(person.reload.wallet.balance_cents).to be > 0
        end
      end

      it "既に購入済みなら二重付与しない" do
        with_env_flag("true") do
          described_class.grant!(person: person, listing: listing)
          result = nil

          expect {
            result = described_class.grant!(person: person, listing: listing)
          }.not_to change(UserPlanSubscription, :count)

          expect(result.duplicate?).to be true
        end
      end
    end

    context "production 環境の場合" do
      it "DisabledError を送出し、購入権利を作成しない" do
        in_production do
          with_env_flag("true") do
            expect {
              expect {
                described_class.grant!(person: person, listing: listing)
              }.to raise_error(DevPersonaPurchase::DisabledError)
            }.not_to change(UserPlanSubscription, :count)
          end
        end
      end
    end
  end
end
