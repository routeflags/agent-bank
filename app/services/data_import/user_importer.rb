# frozen_string_literal: true

require "securerandom"

module DataImport
  # users.csv を 1 行 = 1 ユーザーとして投入する。
  #
  # - 冪等キーは email（emails.address + community_id）
  # - commit: false（既定）では書き込みを一切しない。同じ経路で検証だけを行う
  # - on_conflict: "skip"（既定）/ "update"
  #
  # パスワードは生成してもログ・結果には残さない（出力しない）。
  class UserImporter
    REQUIRED_COLUMNS = %w[email given_name family_name].freeze
    OPTIONAL_COLUMNS = %w[display_name username locale is_admin password].freeze
    ON_CONFLICT_VALUES = %w[skip update].freeze

    DEFAULT_LOCALE = "ja"
    NAME_MAX_LENGTH = 30
    DISPLAY_NAME_MAX_LENGTH = 100
    PASSWORD_MIN_LENGTH = 4
    PASSWORD_GENERATED_BYTES = 12
    USERNAME_FORMAT = /\A[a-z0-9_]+\z/
    # Person の validates :username, length: {within: 3..20} に合わせる。
    USERNAME_MIN_LENGTH = 3
    USERNAME_MAX_LENGTH = 20
    USERNAME_SUFFIX_LIMIT = 100
    # 衝突時に付ける "_NN" の分の余白。
    USERNAME_SUFFIX_ALLOWANCE = 4
    # Email モデルの validates_format_of と同じ形（この正規表現を通ることを保証する）。
    EMAIL_FORMAT = /\A[A-Z0-9._%+\-~\/]+@([A-Z0-9-]+\.)+[A-Z]+\z/i

    class RowError < StandardError; end

    def self.import(path, community: nil, commit: false, on_conflict: "skip")
      new(path, community: community || Community.first, commit: commit, on_conflict: on_conflict).import
    end

    def initialize(path, community:, commit: false, on_conflict: "skip")
      @path = path
      @community = community
      @commit = commit
      @on_conflict = on_conflict.to_s
      validate_options!
    end

    def import
      table = CsvReader.read(path, required: REQUIRED_COLUMNS, optional: OPTIONAL_COLUMNS)
      result = Result.new(ignored_columns: table.ignored_columns)

      table.rows.each { |row| import_row(row, result) }

      result
    end

    private

    attr_reader :path, :community, :on_conflict

    def commit?
      @commit
    end

    def validate_options!
      raise ArgumentError, "コミュニティが見つかりません" if community.nil?

      return if ON_CONFLICT_VALUES.include?(on_conflict)

      raise ArgumentError, "ON_CONFLICT は #{ON_CONFLICT_VALUES.join(' / ')} のいずれかです（指定値: #{on_conflict}）"
    end

    def import_row(row, result)
      email = normalize_email(row["email"])
      raise RowError, "email が空です" if email.empty?
      raise RowError, "email の形式が正しくありません（#{email}）" unless email.match?(EMAIL_FORMAT)

      existing = existing_person(email)

      if existing.nil?
        create_person(row, email, result)
      elsif on_conflict == "update"
        update_person(existing, row, email, result)
      else
        result.add_skipped(
          line: row.line,
          label: email,
          record: existing,
          reason: "同じ email のユーザーが既に存在します（ON_CONFLICT=update で更新できます）"
        )
      end
    rescue RowError => e
      result.add_error(line: row.line, message: e.message)
    rescue ActiveRecord::RecordInvalid => e
      result.add_error(line: row.line, message: e.record.errors.full_messages.join(" / "))
    rescue ActiveRecord::RecordNotUnique => e
      result.add_error(line: row.line, message: "一意制約に違反しました: #{e.message.to_s.lines.first.to_s.strip}")
    end

    def create_person(row, email, result)
      person = Person.new(person_attributes(row, email, existing: nil).merge(community_id: community.id))
      email_record = build_email(person, email)

      persist(person, email_record, row: row, label: email, result: result, action: :created)
    end

    def update_person(person, row, email, result)
      person.assign_attributes(person_attributes(row, email, existing: person))
      email_record = build_email(person, email) if existing_email(person, email).nil?

      persist(person, email_record, row: row, label: email, result: result, action: :updated)
    end

    def persist(person, email_record, row:, label:, result:, action:)
      if commit?
        ActiveRecord::Base.transaction do
          person.save!
          email_record&.save!
        end
      else
        validate_records!(person, email_record)
      end

      if action == :created
        result.add_created(line: row.line, label: label, record: person)
      else
        result.add_updated(line: row.line, label: label, record: person)
      end
    end

    def validate_records!(*records)
      messages = DryRun.validate(*records)
      raise RowError, messages.join(" / ") if messages.any?
    end

    def person_attributes(row, email, existing:)
      given_name = require_text(row, "given_name", max: NAME_MAX_LENGTH)
      family_name = require_text(row, "family_name", max: NAME_MAX_LENGTH)

      attributes = {
        given_name: given_name,
        family_name: family_name,
        display_name: display_name(row, given_name, family_name),
        locale: row["locale"] || DEFAULT_LOCALE,
        is_admin: is_admin(row)
      }

      username = resolve_username(row, email, existing: existing)
      attributes[:username] = username if username

      password = password_from(row)
      if password
        attributes[:password] = password
        attributes[:password_confirmation] = password
      elsif existing.nil?
        generated = SecureRandom.urlsafe_base64(PASSWORD_GENERATED_BYTES)
        attributes[:password] = generated
        attributes[:password_confirmation] = generated
      end

      attributes
    end

    def require_text(row, column, max:)
      value = row[column]
      raise RowError, "#{column} が空です" if value.nil?
      raise RowError, "#{column} は #{max} 文字以内で指定してください（#{value.length} 文字）" if value.length > max

      value
    end

    def display_name(row, given_name, family_name)
      value = row["display_name"] || "#{family_name} #{given_name}"
      if value.length > DISPLAY_NAME_MAX_LENGTH
        raise RowError, "display_name は #{DISPLAY_NAME_MAX_LENGTH} 文字以内で指定してください（#{value.length} 文字）"
      end

      value
    end

    def is_admin(row)
      return 0 if row["is_admin"].nil?

      parsed = Coercion.boolean(row["is_admin"])
      raise RowError, "is_admin は true / false（または 1 / 0）で指定してください（#{row['is_admin']}）" if parsed.nil?

      parsed ? 1 : 0
    end

    def password_from(row)
      value = row["password"]
      return nil if value.nil?
      raise RowError, "password は #{PASSWORD_MIN_LENGTH} 文字以上で指定してください" if value.length < PASSWORD_MIN_LENGTH

      value
    end

    def resolve_username(row, email, existing:)
      given = row["username"]
      return explicit_username(given, existing: existing) if given
      return nil if existing

      derive_available_username(derive_username(email))
    end

    def explicit_username(username, existing:)
      unless username.match?(USERNAME_FORMAT)
        raise RowError, "username は小文字英数字とアンダースコアのみ使用できます（#{username}）"
      end

      unless username.length.between?(USERNAME_MIN_LENGTH, USERNAME_MAX_LENGTH)
        raise RowError, "username は #{USERNAME_MIN_LENGTH}〜#{USERNAME_MAX_LENGTH} 文字で指定してください（#{username}）"
      end

      raise RowError, "username '#{username}' は既に使われています" if username_taken?(username, except: existing)

      username
    end

    def derive_available_username(base)
      USERNAME_SUFFIX_LIMIT.times do |index|
        candidate = index.zero? ? base : "#{base}_#{index}"
        return candidate unless username_taken?(candidate, except: nil)
      end

      raise RowError, "username を自動生成できませんでした（#{base} 系が埋まっています）"
    end

    def derive_username(email)
      base = email.split("@").first.to_s
                  .downcase.gsub(/[^a-z0-9_]/, "_").squeeze("_").gsub(/\A_+|_+\z/, "")
      base = "user" if base.empty?
      base = "#{base}_user" if base.length < USERNAME_MIN_LENGTH

      base[0, USERNAME_MAX_LENGTH - USERNAME_SUFFIX_ALLOWANCE]
    end

    def username_taken?(username, except:)
      return true if Person::USERNAME_BLACKLIST.include?(username.downcase)

      scope = Person.username_exists(username, community)
      scope = scope.where.not(id: except.id) if except
      scope.exists?
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    def existing_person(email)
      email_record = Email.where(address: email, community_id: community.id).order(:id).first
      email_record&.person
    end

    def existing_email(person, email)
      Email.where(person_id: person.id, address: email).first
    end

    def build_email(person, email)
      Email.new(
        person: person,
        address: email,
        community_id: community.id,
        confirmed_at: Time.now,
        send_notifications: true
      )
    end
  end
end
