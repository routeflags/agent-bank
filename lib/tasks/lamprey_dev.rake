# frozen_string_literal: true

# 開発/テスト専用のタスク。
#
# production では実行できない（DevPersonaPurchase が production を拒否する）。
#
# 使い方:
#   bin/rails lamprey:dev:grant_persona[<listing_id>,<person>]
#   # person は Person ID / username / メールアドレスのいずれか
#   bin/rails lamprey:dev:grant_persona[123,buyer@example.com]
namespace :lamprey do
  namespace :dev do
    desc "開発用: 指定ペルソナの購入権利を付与する（実課金なし。production では実行不可）"
    task :grant_persona, [:listing_id, :person] => :environment do |_task, args|
      abort "[lamprey:dev:grant_persona] production では実行できません" if Rails.env.production?

      listing = Listing.find_by(id: args[:listing_id])
      abort "[lamprey:dev:grant_persona] ペルソナ（Listing）が見つかりません: #{args[:listing_id]}" unless listing

      # Person ID / username / メールアドレスのいずれかからユーザーを解決する
      reference = args[:person].to_s.strip
      person = Person.find_by(id: reference) ||
               Person.find_by(username: reference) ||
               Email.find_by(address: reference)&.person
      abort "[lamprey:dev:grant_persona] ユーザーが見つかりません: #{args[:person]}" unless person

      result = DevPersonaPurchase.grant!(person: person, listing: listing)

      if result.duplicate?
        puts "[lamprey:dev:grant_persona] 既に購入済みです: subscription_id=#{result.subscription.id}"
      else
        puts "[lamprey:dev:grant_persona] 購入権利を付与しました: subscription_id=#{result.subscription.id}"
      end
      puts "  person=#{person.username} (#{person.id})"
      puts "  listing=#{listing.id} #{listing.title}"
      puts "  wallet_balance_cents=#{result.wallet&.reload&.balance_cents}"
    end
  end
end
