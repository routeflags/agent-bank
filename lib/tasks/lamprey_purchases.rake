# frozen_string_literal: true

# 管理者（オーナー）による手動付与 Rake タスク（Issue #24）。
#
# 決済手段を持たないコミュニティ（payment_process: none）では、有料ペルソナの
# 購入経路が存在しない（free 遷移では購入権利を付与せず、confirmed 遷移は実決済が
# 必要）。方針として「オーナー（管理者）による明示的な手動付与」を正式な運用経路と
# する:
#   * 決済手段が無い marketplace での検証・販売
#   * Freemius 有効化後の例外対応（返金・オフライン決済の記録など）
# 運用手順・承認フローは documents/guides/manual_purchase_grant.md を参照。
#
# lamprey:dev:grant_persona（DevPersonaPurchase）とは**別物**:
#   * DevPersonaPurchase は「購入の再現」で production では常に無効
#   * 本タスクは「管理者の明示的な付与」で production でも動作する
#     （実決済の代替としてオーナーが判断・記録する正規の経路）
#
# 使い方:
#   bin/rails 'lamprey:purchases:grant[<listing_id>,<person>,<operator>]'
#   bin/rails 'lamprey:purchases:grant[42,alice@example.com,smapira]'
#   # person   は Person ID / username / メールアドレスのいずれか
#   # operator は必須。誰の判断で付与したかを記録する（未指定なら中断）

module LampreyPurchases
  TASK_NAME = "lamprey:purchases:grant"
  PAYMENT_REFERENCE_PREFIX = "manual_grant"

  module_function

  # 監査用の payment_reference を組み立てる。
  # 形式: manual_grant:<operator>:<ISO8601>
  # 後から CreditTransaction.metadata の stripe_payment_id で照会できる。
  def payment_reference_for(operator, time = Time.current)
    "#{PAYMENT_REFERENCE_PREFIX}:#{operator}:#{time.iso8601}"
  end

  # id / username / email のいずれかから Person を解決する（見つからなければ nil）。
  def resolve_person(reference)
    Person.find_by(id: reference) ||
      Person.find_by(username: reference) ||
      Email.find_by(address: reference)&.person
  end

  # 手動付与の本体。タスクからではなくテストからも直接叩けるよう
  # 標準入出力と abort だけをラッパーに置いたクラスとして実装する。
  class Grant
    # @param listing_id [String] 付与対象ペルソナ（Listing）の ID
    # @param person_identifier [String] 付与先 Person の ID / username / email
    # @param operator [String, nil] 付与を判断したオーナーの識別子（必須）
    # @param out [IO] 出力先（既定: $stdout）
    def initialize(listing_id:, person_identifier:, operator:, out: $stdout)
      @listing_id = listing_id
      @person_identifier = person_identifier
      @operator = operator.to_s.strip
      @out = out
    end

    # @return [UserPlanSubscriptionService::Result]
    # @raise [SystemExit] 引数不正・対象不明時（abort）
    def call
      if @operator.blank?
        abort_with("operator が指定されていません。誰の判断で付与したかを記録するため必須です（例: 'lamprey:purchases:grant[42,alice,smapira]'）")
      end

      listing = Listing.find_by(id: @listing_id)
      abort_with("ペルソナ（Listing）が見つかりません: #{@listing_id}") unless listing

      person = LampreyPurchases.resolve_person(@person_identifier.to_s.strip)
      abort_with("ユーザーが見つかりません: #{@person_identifier}") unless person

      payment_reference = LampreyPurchases.payment_reference_for(@operator)
      print_grant_details(listing, person, payment_reference)

      # 購入権利の作成は UserPlanSubscriptionService に集約されている（冪等）。
      # active な購入権利が既にある場合は二重付与せず duplicate が返る。
      result = UserPlanSubscriptionService.create_for(
        person: person,
        listing: listing,
        payment_reference: payment_reference
      )

      if result.duplicate?
        @out.puts "[#{TASK_NAME}] 既に active な購入権利があります。二重付与はしません: subscription_id=#{result.subscription.id}"
      else
        @out.puts "[#{TASK_NAME}] 購入権利を付与しました: subscription_id=#{result.subscription.id}"
        @out.puts "  payment_reference=#{payment_reference}"
      end
      @out.puts "  person=#{person.username} (person_id=#{person.id})"
      @out.puts "  listing=#{listing.id} 「#{listing.title}」"
      @out.puts "  wallet_balance_cents=#{result.wallet&.reload&.balance_cents}"

      # 監査証跡を残す。operator と対象はログにも記録する。
      Rails.logger.info(
        "[#{TASK_NAME}] manual purchase grant: operator=#{@operator} " \
        "person_id=#{person.id} listing_id=#{listing.id} " \
        "subscription_id=#{result.subscription.id} duplicate=#{result.duplicate?} " \
        "payment_reference=#{payment_reference}"
      )

      result
    end

    private

    def abort_with(message)
      abort "[#{TASK_NAME}] #{message}"
    end

    # 誤用防止: 付与前に、実行者が対象と影響範囲（付与トークン数）を
    # 目視確認できるように明細を出力する。production でも実行できるタスクの
    # ため、実行のたびに必ず警告と対象明細を残す。
    def print_grant_details(listing, person, payment_reference)
      included_tokens = BillingConfig.included_tokens(:subscription)
      initial_amount_cents = included_tokens * BillingConfig.per_token_price_cents(:subscription)

      @out.puts "[#{TASK_NAME}] ⚠️  管理者による手動付与を実行します（実決済なし）"
      @out.puts "  この操作は購入権利と初回トークンを付与します。production でも実行できます。"
      @out.puts "  operator      : #{@operator}"
      @out.puts "  person        : #{person.username} (person_id=#{person.id})"
      @out.puts "  listing       : #{listing.id} 「#{listing.title}」 price_cents=#{listing.price_cents} #{listing.currency}"
      @out.puts "  付与トークン数 : #{included_tokens} tokens (initial_amount_cents=#{initial_amount_cents})"
      @out.puts "  payment_ref   : #{payment_reference}"
    end
  end
end

namespace :lamprey do
  namespace :purchases do
    desc "管理者として有料ペルソナの購入権利を手動付与する（実決済なし・operator 必須・production 可）"
    task :grant, %i[listing_id person operator] => :environment do |_task, args|
      LampreyPurchases::Grant.new(
        listing_id: args[:listing_id],
        person_identifier: args[:person],
        operator: args[:operator]
      ).call
    end
  end
end
