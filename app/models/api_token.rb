# frozen_string_literal: true

# == Schema Information
#
# Table name: api_tokens
#
#  id                      :bigint           not null, primary key
#  person_id               :string(22)       not null
#  name                    :string(100)
#  token_digest            :string(255)      not null
#  scopes                  :json
#  last_used_at            :datetime
#  expires_at              :datetime
#  revoked_at              :datetime
#  daily_cost_limit_cents  :integer          default(500), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_api_tokens_on_person_id     (person_id)
#  index_api_tokens_on_token_digest  (token_digest) UNIQUE
#

# MCP（ローカル実行）用のパーソナルアクセストークン（Issue #141）。
#
# 平文トークンは保持しない。`issue!` が返す平文を保存するのは利用者側の
# 責任で、サーバーは SHA-256 digest だけを照合する。
# ローカルプロセス（MCP クライアント）からの Bearer 認証は #142 で有効化した
# （`APIAuthenticatable`）。
#
# 既存の `AuthToken`（unsubscribe / login 用、8 バイト・使い捨て）とは用途も
# 寿命も違うため、別モデル・別テーブルにしている。
#
# クラス名は `inflect.acronym 'API'`（config/initializers/inflections.rb）に従う。
class APIToken < ApplicationRecord
  # 発行できるスコープ。
  #   read — ペルソナの検索・参照（公開情報のみ）
  #   run  — ペルソナの実行（課金を伴う）
  SCOPES = %w[read run].freeze

  # 平文トークンのエントロピー（bytes）。urlsafe_base64 なので 43 文字になる。
  RAW_TOKEN_BYTES = 32

  # 利用者が付ける識別名の最大長。画面の入力欄（maxlength）とサーバー側の
  # 検証を同じ値から導く。
  MAX_NAME_LENGTH = 100

  belongs_to :person

  # MariaDB では json 列が longtext + json_valid チェックでダンプされるため、
  # アダプタは Array にキャストしない（属性が JSON 文字列のままになる）。
  # モデル側では常に Array として扱いたいので明示的にシリアライズする。
  serialize :scopes, coder: JSON

  before_validation :normalize_scopes

  validates :person_id, presence: true
  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :token_digest, presence: true, uniqueness: true
  validates :scopes, presence: true
  validate :scopes_must_be_known

  class << self
    # トークンを発行する。
    #
    # 平文は戻り値でだけ返し、DB には digest のみを保存する。
    #
    # @param person [Person] 所有者
    # @param name [String] 利用者が付ける識別名（例: "Claude Desktop"）
    # @param scopes [Array<String>, String] 許可するスコープ（既定は read のみ）
    # @param expires_at [Time, nil] 有効期限（nil は無期限）
    # @param daily_cost_limit_cents [Integer, nil] 日次コスト上限（nil は DB 既定）
    # @return [Array<APIToken, String>] 発行されたレコードと平文トークン
    # @raise [ActiveRecord::RecordInvalid] 検証に失敗した場合
    def issue!(person:, name:, scopes: ["read"], expires_at: nil, daily_cost_limit_cents: nil)
      raw_token = SecureRandom.urlsafe_base64(RAW_TOKEN_BYTES)

      attributes = {
        person_id: person.id,
        name: name,
        token_digest: digest(raw_token),
        scopes: scopes,
        expires_at: expires_at
      }
      # nil を渡すと DB 既定値を上書きしてしまうので、指定されたときだけ入れる。
      attributes[:daily_cost_limit_cents] = daily_cost_limit_cents if daily_cost_limit_cents

      record = create!(attributes)

      [record, raw_token]
    end

    # 平文トークンから有効なレコードを引く。
    #
    # 未登録・失効済み・期限切れはすべて nil。呼び出し側（#142 の Bearer
    # 認証）は nil を 401 として扱う。
    #
    # @param raw_token [String, nil]
    # @return [APIToken, nil]
    def authenticate(raw_token)
      return nil if raw_token.blank?

      record = find_by(token_digest: digest(raw_token))
      record if record&.active?
    end

    # 平文トークンの照合に使う digest。
    #
    # @param raw_token [String]
    # @return [String] SHA-256 の hex digest
    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end
  end

  # 付与されているスコープの配列。
  #
  # @return [Array<String>]
  def scope_list
    Array(scopes).map(&:to_s)
  end

  # 指定スコープが許可されているか。
  #
  # `run` は `read` を包含する。実行するには対象ペルソナの情報を読む必要が
  # あり、run だけを持つトークンが参照で弾かれると利用者にとって不可解な
  # 失敗になるため。
  #
  # @param scope [String, Symbol] 例: :read, :run
  # @return [Boolean]
  def allows?(scope)
    granted = scope_list
    return granted.include?("read") || granted.include?("run") if scope.to_s == "read"

    granted.include?(scope.to_s)
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # 未失効かつ期限内で、認証に使える状態か。
  def active?
    !revoked? && !expired?
  end

  # 失効させる。既に失効済みなら何もしない（冪等）。
  #
  # @return [APIToken] self
  def revoke!
    return self if revoked?

    update!(revoked_at: Time.current)
    self
  end

  # 認証成功時に最終使用日時を記録する。
  #
  # 認証は全リクエストで走るため、`updated_at` を動かさず検証もスキップする
  # 更新にしている。呼び出し側（`APIAuthenticatable`）が 1 分間引いてから
  # 呼ぶので、毎リクエストの UPDATE にはならない。
  #
  # @return [Boolean]
  def touch_last_used!
    update_columns(last_used_at: Time.current)
  end

  private

  # 文字列・配列のどちらでも受け取り、空白と重複を落とす。
  def normalize_scopes
    self.scopes = Array(scopes).map { |scope| scope.to_s.strip }.reject(&:blank?).uniq
  end

  def scopes_must_be_known
    unknown = scope_list - SCOPES
    return if unknown.empty?

    errors.add(:scopes, "に不明なスコープが含まれています: #{unknown.join(', ')}")
  end
end
