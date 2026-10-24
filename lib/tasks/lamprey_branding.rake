# frozen_string_literal: true

# 消費者向け表記を「楽市楽問」に統一する Rake タスク（Issue #38）。
#
# 背景: community_customizations に ja 行が存在せず、`%{service_name}` 経由の
# 表示（新規登録見出し・ページタイトル等）が en 行の "Agent Bank" に
# フォールバックしていた。また利用規約の日本文面が未設定のため、
# 英語デフォルト文面（Terms of Service for ...）が表示されていた。
#
# 方針:
#   * 対象は ja ロケールの名称・利用規約のみ。en 行は残す（フォールバック用）。
#   * 既にオーナーが独自に設定した文言（"Agent Bank" でも blank でもない値）は
#     上書きしない（破壊的変更の禁止）。
#   * 対象コミュニティは ident 'agent-bank' に限定する。
#     引数 community_id で明示指定もできる。
#   * 何度実行しても同じ結果になる（冪等）。
#
# 使い方:
#   bin/rails 'lamprey:branding:unify_service_name'      # ident agent-bank の community
#   bin/rails 'lamprey:branding:unify_service_name[6]'   # community_id=6 を明示

module LampreyBranding
  TASK_NAME = "lamprey:branding:unify_service_name"
  SERVICE_NAME_JA = "楽市楽問"
  LEGACY_NAME = "Agent Bank"
  LAMPREY_IDENT = "agent-bank"
  JA_LOCALE = "ja"

  module_function

  # 利用規約の日本語ベース文面（HTML）。community_customizations の
  # terms_page_content に投入する。法務的な確定版ではなくベースラインであり、
  # 既存の独自文言は上書きしない。確定版の確認はオーナーが行う。
  def terms_ja
    <<~HTML
      <h2>楽市楽問 利用規約</h2>
      <p>この利用規約（以下「本規約」といいます）は、楽市楽問（以下「本サービス」といいます）の利用条件を定めるものです。本サービスを利用するすべての方（以下「利用者」といいます）は、本規約に同意のうえ利用するものとします。</p>
      <h3>第1条（本サービス）</h3>
      <p>本サービスは、AIペルソナの出品・購入およびチャット機能を提供するマーケットプレイスです。</p>
      <h3>第2条（利用登録）</h3>
      <p>利用者は、正確な情報をもって登録するものとします。登録情報に虚偽があった場合、運営者は利用を制限できるものとします。</p>
      <h3>第3条（禁止事項）</h3>
      <p>利用者は、法令または公序良俗に反する行為、他の利用者に迷惑をかける行為、本サービスの運営を妨げる行為を行ってはなりません。</p>
      <h3>第4条（決済）</h3>
      <p>有料機能の料金および決済方法は、本サービス上の表示に従うものとします。</p>
      <h3>第5条（免責）</h3>
      <p>AIによる応答内容の正確性・完全性について、運営者は保証しません。重要な判断は利用者ご自身の責任で行ってください。</p>
      <h3>第6条（本規約の変更）</h3>
      <p>運営者は、必要に応じて本規約を変更できるものとします。変更後に本サービスを利用した場合は、変更に同意したものとみなします。</p>
      <p>以上</p>
    HTML
  end

  # 旧ブランド名のまま（= 統一対象）かどうか。
  def legacy_name?(name)
    name.blank? || name == LEGACY_NAME
  end

  # 英語デフォルト文面のまま（= 投入対象）かどうか。
  def legacy_terms?(content)
    content.blank? || content.include?("Terms of Service for")
  end

  # 表記統一の本体。タスクからではなくテストからも直接叩けるよう
  # 標準入出力と abort だけをラッパーに置いたクラスとして実装する。
  class UnifyServiceName
    # @param community_id [String, nil] 対象 community の ID（省略時は ident 解決）
    # @param out [IO] 出力先（既定: $stdout）
    def initialize(community_id: nil, out: $stdout)
      @community_id = community_id.to_s.strip
      @out = out
    end

    # @return [Array<Hash>] community ごとの適用結果
    # @raise [SystemExit] 対象不明時（abort）
    def call
      communities = resolve_targets
      abort_with("対象のコミュニティが見つかりません（community_id=#{@community_id.presence || "(ident:#{LampreyBranding::LAMPREY_IDENT})"}）") if communities.empty?

      communities.map { |community| unify(community) }
    end

    private

    def resolve_targets
      if @community_id.present?
        community = Community.find_by(id: @community_id)
        return community ? [community] : []
      end

      Community.where(ident: LampreyBranding::LAMPREY_IDENT).to_a
    end

    def unify(community)
      customization = community.community_customizations.find_or_initialize_by(
        locale: LampreyBranding::JA_LOCALE
      )

      changed = []
      if LampreyBranding.legacy_name?(customization.name)
        customization.name = LampreyBranding::SERVICE_NAME_JA
        changed << "name"
      end
      if LampreyBranding.legacy_terms?(customization.terms_page_content)
        customization.terms_page_content = LampreyBranding.terms_ja
        changed << "terms_page_content"
      end
      customization.save! if changed.any?

      if changed.any?
        @out.puts "[#{LampreyBranding::TASK_NAME}] 更新: community_id=#{community.id} ident=#{community.ident} (#{changed.join(', ')})"
      else
        @out.puts "[#{LampreyBranding::TASK_NAME}] 変更なし: community_id=#{community.id} ident=#{community.ident}（独自文言を維持）"
      end

      Rails.logger.info(
        "[#{LampreyBranding::TASK_NAME}] community_id=#{community.id} changed=#{changed.join(',')}"
      )

      { community_id: community.id, changed: changed }
    end

    def abort_with(message)
      abort "[#{LampreyBranding::TASK_NAME}] #{message}"
    end
  end
end

namespace :lamprey do
  namespace :branding do
    desc "消費者向け表記を「楽市楽問」に統一する（ja 名称・利用規約を冪等投入。Issue #38）"
    task :unify_service_name, [:community_id] => :environment do |_task, args|
      LampreyBranding::UnifyServiceName.new(
        community_id: args[:community_id]
      ).call
    end
  end
end
