# frozen_string_literal: true

# Issue #138: 既存出品を「チャットで動くペルソナ」の状態に揃える。
#
# CSV/シード取り込みで作った出品は `default_run_mode='download'` かつ
# `listing_ai_models` が空のため、出品ページにチャットパネルが出ず、
# 「利用する」を押すと取引メッセージ画面へ流れてしまう。
# 画面から出品した場合の既定（`run_online` + 既定 AI モデル）に揃える。
#
#   bin/rails "lamprey:enable_persona_chat"            # ドライラン
#   COMMIT=1 bin/rails "lamprey:enable_persona_chat"   # 適用
module LampreyPersonaChat
  module_function

  # @return [Array<Hash>] 対象（不足している項目を flags で持つ）
  def targets
    Listing.unscoped.where(deleted: false).order(:id).filter_map do |listing|
      missing_mode = listing.default_run_mode != PersonaDefaults.run_mode
      missing_model = listing.listing_ai_models.empty?
      next unless missing_mode || missing_model

      { listing: listing, mode: missing_mode, model: missing_model }
    end
  end

  def run(apply:)
    puts "[lamprey:enable_persona_chat] mode=#{apply ? 'commit' : 'dry-run'}"
    puts "既定モデル: #{PersonaDefaults.ai_model&.name || '(未設定)'}"

    list = targets
    if list.empty?
      puts "対象 0 件（すべてチャット可能な状態）"
      return
    end

    list.each do |t|
      flags = [t[:mode] ? 'run_mode' : nil, t[:model] ? 'ai_model' : nil].compact.join('+')
      puts "  ##{t[:listing].id} #{t[:listing].title} (#{flags})"
    end
    puts "対象 #{list.size} 件"

    if apply
      list.each do |t|
        listing = t[:listing]
        if t[:mode]
          listing.default_run_mode = PersonaDefaults.run_mode
          listing.supported_run_modes = PersonaDefaults.supported_run_modes
          listing.save!
        end
        PersonaDefaults.ensure_default_ai_model!(listing) if t[:model]
      end
      puts "適用しました: #{list.size} 件"
    else
      puts 'ドライラン: DB は変更していません。適用するには COMMIT=1 を付けて再実行してください。'
    end
  end
end

namespace :lamprey do
  desc '既存出品にペルソナチャットの既定（run_online + 既定 AI モデル）を適用する（COMMIT=1 で適用）'
  task enable_persona_chat: :environment do
    LampreyPersonaChat.run(apply: ENV['COMMIT'].to_s == '1')
  end
end
