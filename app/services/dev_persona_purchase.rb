# frozen_string_literal: true

# 開発/テスト環境専用のペルソナ購入（購入権利の付与）ヘルパー。
#
# 本番の購入フローは Freemius（Merchant of Record）の決済完了を経て
# UserPlanSubscription を作成する。実課金を行わずに「購入済み」状態を
# 再現してよいのは開発・テストだけなので、二重のガードで保護する。
#
#   1. Rails.env.production? では常に無効（フラグ値によらない）
#   2. development / test でも ENV["LAMPREY_ENABLE_DEV_PURCHASE"] が真のときのみ有効
#
# 2 のフラグが無い限り、開発環境でも勝手に購入権利は付与されない。
# ウォレットチャージの開発用擬似決済（API::V1::WalletTopupController#dev_mode_topup?）
# と同じ考え方で、本番に購入偽装の経路を残さないことを目的とする。
#
# 利用箇所:
#   * API::V1::Dev::PersonaPurchasesController（HTTP・開発時の検証用）
#   * lamprey:dev:grant_persona（Rake・サーバーを起動しない検証用）
# （Issue #51: チャット UI からの購入導線は撤去済み。本番の購入概念は持たない）
module DevPersonaPurchase
  class DisabledError < StandardError; end

  ENABLE_FLAG = "LAMPREY_ENABLE_DEV_PURCHASE"

  class << self
    # 開発購入が有効か。production ではフラグ値に関わらず必ず false。
    #
    # @return [Boolean]
    def enabled?
      return false if Rails.env.production?

      dev_env? && flag_enabled?
    end

    # 購入権利を付与する（実決済は行わない）。
    #
    # HTTP 経由では enabled? を事前に確認すること。Rake タスクのように
    # オペレーターが明示的に実行する経路では、フラグではなく実行環境のみで
    # 判定するため、こちらを直接呼ぶ。
    #
    # @param person [Person]
    # @param listing [Listing]
    # @return [UserPlanSubscriptionService::Result]
    # @raise [DisabledError] production 環境で呼ばれた場合
    def grant!(person:, listing:)
      raise DisabledError, "開発用の購入付与は production では実行できません" unless dev_env?

      UserPlanSubscriptionService.create_for(
        person: person,
        listing: listing,
        payment_reference: "dev_purchase_#{SecureRandom.hex(8)}"
      )
    end

    private

    def dev_env?
      Rails.env.development? || Rails.env.test?
    end

    def flag_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV[ENABLE_FLAG]) == true
    end
  end
end
