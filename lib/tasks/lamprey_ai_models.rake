# frozen_string_literal: true

# Issue #105: ai_models.max_tokens の是正（出力上限に統一する）。
#
# 現状 gpt-4o / gpt-4o-mini にはコンテキスト長（128000）が入っているが、
# max_tokens は出力上限の意味で使うため 16384 に是正する。
# 他モデルは現行値を維持する。既存カラムの値更新のみでマイグレーションは不要。
# 何度実行しても同じ結果になる（冪等）。
#
#   bin/rails 'lamprey:ai_models:fix_max_tokens'
namespace :lamprey do
  namespace :ai_models do
    desc "gpt-4o / gpt-4o-mini の max_tokens を出力上限（16384）に是正する"
    task fix_max_tokens: :environment do
      corrections = {
        "gpt-4o" => 16_384,
        "gpt-4o-mini" => 16_384
      }

      corrections.each do |slug, max_tokens|
        model = AiModel.find_by(slug: slug)
        if model.nil?
          puts "スキップ: #{slug} が見つかりません"
          next
        end

        if model.max_tokens == max_tokens
          puts "変更なし: #{slug} (max_tokens=#{model.max_tokens})"
        else
          model.update!(max_tokens: max_tokens)
          puts "更新しました: #{slug} (max_tokens=#{model.max_tokens})"
        end
      end
    end
  end
end
