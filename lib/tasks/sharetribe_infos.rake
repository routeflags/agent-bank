# frozen_string_literal: true

# 法定ページ（利用規約 / プライバシーポリシー / このサイトについて）の
# community_customizations 上書きを解除する、一度きりの移行タスク。
#
# 背景: infos の各ページは community_customizations の *_page_content が
# 優先表示される。本番 DB には旧・短い利用規約などが残っており、ビュー側の
# 版管理された法定文言を修正してもそちらが表示されるため、リリースに伴い
# 一度だけ手動で実行して上書きを取り除く。
#
# 方針:
#   * 対象は全 community の全 community_customizations 行。
#   * terms / privacy / about の 3 カラムを nil にするだけ。他の値は触らない。
#   * バリデーションとコールバックを通さない（update_columns）。
#   * 何度実行しても同じ結果になる（冪等）。
#   * deploy スクリプトには組み込まない。毎回消すと管理画面から入力した独自
#     文言まで失われるため、実行は人の判断で一度だけ行う。
#
# 注意:
#   * lamprey:branding:unify_service_name は terms_page_content にベースライン
#     文面を投入する。本タスクの後に同タスクを再実行すると上書きが復活する。
#
# 使い方:
#   bin/rails 'sharetribe:infos:clear_page_overrides'
namespace :sharetribe do
  namespace :infos do
    desc "法定ページの DB 上書き（terms/privacy/about）を全 community で解除する一度きりの移行"
    task clear_page_overrides: :environment do
      task_name = "sharetribe:infos:clear_page_overrides"
      columns = %w[terms_page_content privacy_page_content about_page_content]
      cleared = 0

      CommunityCustomization.find_each do |customization|
        present = columns.select { |column| customization.public_send(column).present? }
        next if present.empty?

        customization.update_columns(present.index_with(nil).symbolize_keys)
        cleared += 1
        puts "[#{task_name}] 解除: id=#{customization.id} community_id=#{customization.community_id} " \
             "locale=#{customization.locale} (#{present.join(', ')})"
      end

      puts "[#{task_name}] 完了: #{cleared} 件の行の上書きを解除しました"
    end
  end
end
