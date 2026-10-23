# frozen_string_literal: true

# Issue #25: 逆ガード（free 遷移での誤付与）により購入権利・初回トークンが
# 付与済みの可能性がある取引を、読み取り専用で監査する Rake タスク群。
#
# 使い方:
#   bin/rails 'lamprey:audit:free_grants'                       # 全件
#   bin/rails 'lamprey:audit:free_grants[2026-01-01,2026-12-31]'
#   bin/rails 'lamprey:audit:free_grants[2026-01-01,2026-12-31,3]'  # community_id=3
#
# 監査手順・出力の読み方・巻き戻し判断の材料は
# documents/guides/free_grant_audit.md を参照。
module LampreyAudit
  module_function

  # 引数の日付（YYYY-MM-DD 等）を Date に変換する。未指定なら nil。
  def parse_date(value, name)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    abort "[lamprey:audit:free_grants] #{name} の日付を解釈できません: #{value}（例: 2026-01-01）"
  end

  # 引数の community_id を整数に変換する。未指定なら nil。
  def parse_community_id(value)
    return nil if value.blank?

    Integer(value.to_s, 10)
  rescue ArgumentError
    abort "[lamprey:audit:free_grants] community_id が整数ではありません: #{value}"
  end

  # `free` 状態で完了し listing の価格が正の取引を対象に、
  # 購入権利（UserPlanSubscription）と初回トークン付与
  # （Wallet / CreditTransaction）を突合する読み取り専用の監査。
  #
  # 発行する SQL は SELECT のみ。さらに実行中は MySQL セッションを
  # READ ONLY に設定し、誤って書き込みが発生しても DB 側で拒否される。
  class FreeGrants
    # 判定区分（サマリの集計順 = この定義順）。
    VERDICT_LABELS = {
      rollback: "巻き戻し候補（この取引の free 遷移で付与された直接証拠あり）",
      judgment: "要判断（この取引由来トークン＋実購入の裏付けあり）",
      unresolved: "要確認（購入権利はあるが付与経路の証拠なし）",
      legit: "実購入の裏付けあり（巻き戻し不要の可能性）",
      none: "付与なし"
    }.freeze

    # @param since [Date, nil] 対象期間の開始（含む）
    # @param until_date [Date, nil] 対象期間の終了（含む）
    # @param community_id [Integer, nil] community で絞り込む
    # @param out [IO] 出力先（既定: $stdout）
    def initialize(since: nil, until_date: nil, community_id: nil, out: $stdout)
      @since = since&.beginning_of_day
      @until = until_date&.end_of_day
      @community_id = community_id
      @out = out
      @session_read_only = false
    end

    # 監査を実行し、結果を行数ぶんの配列（row）で返す。
    # @return [Array<Hash>]
    def run
      rows = read_only do
        print_header
        candidates.map { |tx| audit_transaction(tx) }
      end
      rows.each_with_index { |row, index| print_detail(row, index + 1) }
      print_summary(rows)
      rows
    end

    private

    # セッションを READ ONLY にしてブロックを実行し、終了時に元に戻す。
    # テスト等で既にトランザクションが開いている場合は、そのトランザクションに
    # 効く「次のトランザクション」の既定値として設定されるだけで副作用はない。
    def read_only
      ActiveRecord::Base.connection.execute("SET SESSION TRANSACTION READ ONLY")
      @session_read_only = true
      yield
    ensure
      if @session_read_only
        ActiveRecord::Base.connection.execute("SET SESSION TRANSACTION READ WRITE")
        @session_read_only = false
      end
    end

    # 旧逆ガードの条件と同値の対象抽出。
    #   * current_state = 'free'（free 遷移で完了）
    #   * listings.price_cents > 0（旧実装は listing.price.positive? で付与）
    # 期間は free 遷移時刻（last_transition_at、なければ created_at）で判定する。
    def candidates
      scope = Transaction
              .joins(:listing)
              .where(current_state: "free")
              .where("listings.price_cents > 0")
      scope = scope.where(community_id: @community_id) if @community_id
      if @since
        scope = scope.where("COALESCE(transactions.last_transition_at, transactions.created_at) >= ?", @since)
      end
      if @until
        scope = scope.where("COALESCE(transactions.last_transition_at, transactions.created_at) <= ?", @until)
      end
      scope.includes(:starter, :listing).order(Arel.sql("transactions.id"))
    end

    # 1 取引ぶんの突合結果を集める。
    def audit_transaction(tx)
      buyer = tx.starter
      listing = tx.listing
      subscriptions = UserPlanSubscription.where(person_id: buyer.id, listing_id: listing.id).order(:id).to_a
      wallet = Wallet.find_by(person_id: buyer.id, community_id: listing.community_id)
      topups = purchase_topups_for(buyer)

      expected_ref = "initial_purchase_#{tx.id}"
      this_grant = topups.find { |(_, ref)| ref == expected_ref }
      purchase_grants, non_purchase = topups.partition { |(_, ref)| ref.match?(%r{\Ainitial_purchase_\d+\z}) }
      other_grants = purchase_grants - [this_grant].compact
      dev_grants = non_purchase.select { |(_, ref)| ref.start_with?("dev_purchase_") }

      paid_tx_ids = Transaction
                    .where(starter_id: buyer.id, listing_id: listing.id, current_state: "confirmed")
                    .order(:id)
                    .pluck(:id)
      matched_paid_ids = topups.filter_map { |(_, ref)| ref[%r{\Ainitial_purchase_(\d+)\z}, 1]&.to_i } & paid_tx_ids

      {
        transaction: tx,
        wallet: wallet,
        subscriptions: subscriptions,
        this_grant: this_grant,
        other_grants: other_grants,
        dev_grants: dev_grants,
        paid_tx_ids: paid_tx_ids,
        matched_paid_ids: matched_paid_ids,
        verdict: decide(subscriptions: subscriptions, this_grant: this_grant, legit_paid: paid_tx_ids.any?)
      }
    end

    # 購買系 topup のうち payment_reference を持つものだけを
    # [CreditTransaction, reference] のペアで返す。
    def purchase_topups_for(buyer)
      CreditTransaction
        .joins(:wallet)
        .where(wallets: { person_id: buyer.id }, transaction_type: "topup")
        .includes(:wallet)
        .filter_map do |ct|
          ref = parse_stripe_payment_id(ct)
          [ct, ref] if ref.present?
        end
    end

    def parse_stripe_payment_id(credit_transaction)
      JSON.parse(credit_transaction.metadata.to_s)["stripe_payment_id"]
    rescue JSON::ParserError
      nil
    end

    # 判定（証拠の強い順）。
    #   1. 購入権利もこの取引由来トークンも無い → 付与なし
    #   2. この取引由来トークン ＋ 同一 buyer×listing の実購入(confirmed)あり → 要判断
    #   3. この取引由来トークンあり → 巻き戻し候補（逆ガードの直接証拠）
    #   4. 実購入(confirmed)あり → 実購入の裏付け（正当な付与経路）
    #   5. 購入権利のみ → 付与経路の証拠なし → 要確認
    def decide(subscriptions:, this_grant:, legit_paid:)
      if subscriptions.empty? && this_grant.nil?
        :none
      elsif this_grant && legit_paid
        :judgment
      elsif this_grant
        :rollback
      elsif legit_paid
        :legit
      else
        :unresolved
      end
    end

    # ── 出力 ──────────────────────────────────────────────

    def print_header
      @out.puts "[lamprey:audit:free_grants] 読み取り専用監査（Issue #25）"
      @out.puts "  対象    : free 状態で完了し listing 価格が正の取引（旧逆ガードの対象）"
      @out.puts "  実行条件: #{filter_description}"
    end

    def print_detail(row, index)
      tx = row[:transaction]
      @out.puts "##{index} transaction_id=#{tx.id} current_state=#{tx.current_state} deleted=#{tx.deleted}"
      @out.puts "  buyer      : #{tx.starter.username} (person_id=#{tx.starter_id})"
      @out.puts "  listing    : listing_id=#{tx.listing_id} 「#{tx.listing.title}」 price_cents=#{tx.listing.price_cents} #{tx.listing.currency}（監査時点の値）"
      free_at, free_source = free_finished_at(tx)
      @out.puts "  free完了   : #{free_at&.to_fs(:db)} (#{free_source})"
      @out.puts(
        if row[:wallet]
          "  wallet     : wallet_id=#{row[:wallet].id} balance_cents=#{row[:wallet].balance_cents} #{row[:wallet].currency}"
        else
          "  wallet     : なし"
        end
      )
      print_subscriptions(row[:subscriptions])
      print_token_evidence(row)
      print_paid_evidence(row)
      @out.puts "  判定       : #{VERDICT_LABELS.fetch(row[:verdict])}"
      @out.puts ""
    end

    def print_subscriptions(subscriptions)
      if subscriptions.empty?
        @out.puts "  購入権利   : なし"
        return
      end

      subscriptions.each do |sub|
        @out.puts "  購入権利   : subscription_id=#{sub.id} status=#{sub.status} billing_model=#{sub.billing_model} created_at=#{sub.created_at.to_fs(:db)}"
      end
    end

    def print_token_evidence(row)
      printed = false
      if row[:this_grant]
        credit_tx, reference = row[:this_grant]
        @out.puts "  初回トークン: credit_transaction_id=#{credit_tx.id} amount_cents=#{credit_tx.amount_cents} reference=#{reference} ←この取引由来"
        printed = true
      end
      row[:other_grants].each do |other_tx, other_ref|
        @out.puts "  初回トークン: 参考 他取引由来 reference=#{other_ref} (credit_transaction_id=#{other_tx.id} amount_cents=#{other_tx.amount_cents})"
        printed = true
      end
      row[:dev_grants].each do |dev_tx, dev_ref|
        @out.puts "  初回トークン: 参考 開発用付与 reference=#{dev_ref} (credit_transaction_id=#{dev_tx.id} amount_cents=#{dev_tx.amount_cents})"
        printed = true
      end
      @out.puts "  初回トークン: なし" unless printed
    end

    def print_paid_evidence(row)
      if row[:paid_tx_ids].empty?
        @out.puts "  実購入     : なし（同一 buyer×listing の confirmed 取引なし）"
        return
      end

      row[:paid_tx_ids].each do |paid_id|
        marker = row[:matched_paid_ids].include?(paid_id) ? "reference一致" : "reference未確認"
        @out.puts "  実購入     : transaction_id=#{paid_id} (confirmed, #{marker})"
      end
    end

    def print_summary(rows)
      counts = VERDICT_LABELS.keys.index_with { |verdict| rows.count { |row| row[:verdict] == verdict } }
      attention = counts[:rollback] + counts[:judgment] + counts[:unresolved]

      @out.puts "---"
      @out.puts "[lamprey:audit:free_grants] サマリ"
      @out.puts "  対象（free×有料 listing） : #{rows.size} 件"
      counts.each { |verdict, count| @out.puts "  #{VERDICT_LABELS.fetch(verdict)} : #{count} 件" }
      @out.puts "  オーナー判断が必要（巻き戻し候補＋要判断＋要確認） : #{attention} 件"
      @out.puts "  実行条件: #{filter_description}"
      @out.puts "  書き込み: なし（SELECT のみ。実行中セッションを READ ONLY に設定）"
    end

    def free_finished_at(tx)
      return [tx.last_transition_at, "last_transition_at"] if tx.last_transition_at.present?

      [tx.created_at, "created_at"]
    end

    def filter_description
      period = if @since || @until
                 "#{@since ? @since.to_date : '未指定'} 〜 #{@until ? @until.to_date : '未指定'}"
               else
                 "全期間"
               end
      "期間=#{period} community_id=#{@community_id || '全件'}"
    end
  end
end

namespace :lamprey do
  namespace :audit do
    desc "free 遷移×有料 listing の取引について、購入権利と初回トークン付与を読み取り専用で突合する（Issue #25）"
    task :free_grants, %i[since until community_id] => :environment do |_task, args|
      since = LampreyAudit.parse_date(args[:since], "since")
      until_date = LampreyAudit.parse_date(args[:until], "until")
      community_id = LampreyAudit.parse_community_id(args[:community_id])

      if since && until_date && since > until_date
        abort "[lamprey:audit:free_grants] since が until より後になっています: #{since} > #{until_date}"
      end

      LampreyAudit::FreeGrants.new(
        since: since,
        until_date: until_date,
        community_id: community_id
      ).run
    end
  end
end
