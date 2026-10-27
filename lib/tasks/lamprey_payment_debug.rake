# frozen_string_literal: true

# 決済 1 件を追いかけるデバッグ用タスク。
#
# 「Freemius では決済されているのに残高が増えない」ときに、
# Freemius 側の決済 → plan の解決 → ローカルのユーザー/ウォレット → 加算記録
# を 1 コマンドで並べて確認できるようにする（読み取りのみ）。
#
# 使い方:
#   bin/rails 'lamprey:debug:payment[2177322]'
namespace :lamprey do
  namespace :debug do
    desc "決済 1 件の状態を表示する（Freemius 側 + ローカル。読み取りのみ）"
    task :payment, [:payment_id] => :environment do |_task, args|
      payment_id = args[:payment_id].to_s.strip
      abort "[lamprey:debug:payment] payment_id を指定してください" if payment_id.empty?

      puts "== 設定 =="
      puts "  FreemiusClient.configured?   = #{FreemiusClient.configured?}"
      puts "  FreemiusPricing.configured?  = #{FreemiusPricing.configured?} (rate=#{FreemiusPricing.rate.inspect})"
      puts "  FreemiusTopupPlans.configured? = #{FreemiusTopupPlans.configured?}"
      unless FreemiusTopupPlans.validation_errors.empty?
        puts "  額面 MAP の検証エラー: #{FreemiusTopupPlans.validation_errors.join('; ')}"
      end

      puts "== Freemius 側の決済 (#{payment_id}) =="
      remote = nil
      begin
        remote = FreemiusClient.get_payment(payment_id)
        remote = remote["payments"].first if remote["payments"].is_a?(Array)
        plan_id = remote["plan_id"] || remote[:plan_id]
        puts "  plan_id = #{plan_id.inspect}"
        puts "  gross   = #{remote['gross'].inspect} #{remote['currency']}"
        puts "  金額(cents) = #{FreemiusClient.payment_amount_cents(remote)}"
        puts "  作成    = #{remote['created'].inspect}"
        credit = plan_id && FreemiusTopupPlans.credit_for_plan(plan_id.to_s)
        puts "  MAP の付与額 = #{credit.inspect} 円"
        puts "  ※ MAP 未登録の plan の場合、webhook は何も加算しません" if plan_id && credit.nil?
        # Issue #53: 付与円×レートと plan 価格の比較（逆ザヤ判定用）。
        # 正常マージン例: plan 74358 = $5.00 (500c) / 付与 600円 (rate 0.0065 -> 390c)。
        if plan_id && credit
          begin
            converted = FreemiusPricing.configured? ? FreemiusPricing.usd_cents_for_jpy(credit) : nil
            expected = FreemiusPricing.plan_price_map[plan_id.to_s]
            puts "  付与額のUSD換算 = #{converted.inspect}c (rate=#{FreemiusPricing.rate.inspect})"
            puts "  期待plan価格 = #{expected.inspect}c (FREEMIUS_PLAN_PRICE_MAP)"
            if converted && expected
              if converted >= expected.to_i
                puts "  逆ザヤ判定 = NG（付与額の換算 >= plan価格。赤字のため MAP/価格を見直す）"
              else
                puts "  逆ザヤ判定 = OK（顧客負担 >= 付与額。マージン #{expected.to_i - converted}c）"
              end
            else
              puts "  逆ザヤ判定 = 不明（レートまたは価格マップ未設定）"
            end
          rescue FreemiusPricing::RateMissingError
            puts "  逆ザヤ判定 = 不明（レート未設定）"
          end
        end
      rescue FreemiusClient::ApiError => e
        puts "  取得失敗: #{e.message[0, 160]}"
        puts "  ※ API 失敗でも webhook は署名を正として付与します（額面 MAP がある場合）"
      end

      email = remote && (remote["user_email"] || remote.dig("user", "email"))
      email ||= remote && remote["user"].is_a?(Array) && remote["user"].first&.dig("email")
      # payment には user_id（Freemius のユーザー ID）しか乗らないため、
      # API でユーザーを引いてメールアドレスを補完する（デバッグ用）。
      if email.blank? && remote && remote["user_id"].present?
        begin
          user = FreemiusClient.get_user(remote["user_id"])
          user = user["users"].first if user["users"].is_a?(Array)
          email = user["email"]
        rescue FreemiusClient::ApiError => e
          puts "  user 取得失敗: #{e.message[0, 120]}"
        end
      end
      puts "  user_email = #{email.inspect}"

      puts "== ローカル側 =="
      person = email ? Person.by_email(email.to_s.downcase).first : nil
      if person.nil?
        puts "  ユーザーが見つかりません（メール一致なし）。webhook はユーザー特定でスキップします"
      else
        puts "  person = #{person.id} (#{person.username})"
        wallet = Wallet.where(person_id: person.id).first
        puts "  wallet = #{wallet&.id} balance = #{wallet&.balance_cents}"
      end

      txs = CreditTransaction.where("metadata LIKE ?", "%#{payment_id}%").order(:id)
      puts "  この決済を参照する加算記録: #{txs.count} 件"
      txs.each do |tx|
        a = tx.attributes
        puts "    id=#{a['id']} wallet=#{a['wallet_id']} amount=#{a['amount_cents']} type=#{a['transaction_type']} created=#{a['created_at']}"
      end

      puts "== 判定 =="
      if txs.any?
        puts "  加算済み。二重加算されないことを確認するには webhook を再送しても件数が変わらないことを見る"
      else
        puts "  未加算。確認順: (1) webhook 到達（ログの status 200/401） (2) イベント種別 (3) plan の MAP 登録 (4) ユーザー特定"
      end
    end
  end
end
