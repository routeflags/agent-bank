# frozen_string_literal: true

module DataImport
  # listings.csv を 1 行 = 1 出品（ペルソナ）として投入する。
  #
  # - 冪等キーは (title, author_id)（deleted: false のものだけを見る）
  # - commit: false（既定）では書き込みを一切しない。同じ経路で検証だけを行う
  # - on_conflict: "skip"（既定）/ "update"
  class ListingImporter
    REQUIRED_COLUMNS = %w[title price_cents author_email].freeze
    OPTIONAL_COLUMNS = %w[description skill_markdown category open currency listing_shape].freeze
    ON_CONFLICT_VALUES = %w[skip update].freeze

    TITLE_MIN_LENGTH = 2
    TITLE_MAX_LENGTH = 65
    DEFAULT_CURRENCY = "JPY"
    CURRENCY_FORMAT = /\A[A-Z]{3}\z/
    # 「システム用カテゴリ」は公開ナビに出さない（HomepageController と同じ扱い）。
    SYSTEM_CATEGORY_URLS = %w[default-category].freeze

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
      attributes = listing_attributes(row)
      warning = skill_markdown_warning(row)
      label = "#{attributes[:title]} (#{attributes[:author].username})"

      existing = find_listing(attributes[:title], attributes[:author])

      if existing.nil?
        create_listing(attributes, row, label, warning, result)
      elsif on_conflict == "update"
        update_listing(existing, attributes, row, label, warning, result)
      else
        result.add_skipped(
          line: row.line,
          label: label,
          record: existing,
          reason: "同じ title / author の出品が既に存在します（ON_CONFLICT=update で更新できます）"
        )
      end
    rescue RowError => e
      result.add_error(line: row.line, message: e.message)
    rescue ActiveRecord::RecordInvalid => e
      result.add_error(line: row.line, message: e.record.errors.full_messages.join(" / "))
    rescue ActiveRecord::RecordNotUnique => e
      result.add_error(line: row.line, message: "一意制約に違反しました: #{e.message.to_s.lines.first.to_s.strip}")
    end

    def create_listing(attributes, row, label, warning, result)
      listing = Listing.new(model_attributes(attributes).merge(community_id: community.id))
      persist(listing, row: row, label: label, warning: warning, result: result, action: :created)
    end

    def update_listing(listing, attributes, row, label, warning, result)
      listing.assign_attributes(model_attributes(attributes))
      persist(listing, row: row, label: label, warning: warning, result: result, action: :updated)
    end

    # CSV の 1 行から組み立てた属性を、Listing のカラムに詰め替える。
    def model_attributes(attributes)
      {
        title: attributes[:title],
        description: attributes[:description],
        skill_markdown: attributes[:skill_markdown],
        price_cents: attributes[:price_cents],
        currency: attributes[:currency],
        author_id: attributes[:author].id,
        category: attributes[:category],
        listing_shape: attributes[:listing_shape],
        open: attributes[:open]
      }
    end

    def persist(listing, row:, label:, warning:, result:, action:)
      if commit?
        ActiveRecord::Base.transaction { listing.save! }
      else
        messages = DryRun.validate(listing)
        raise RowError, messages.join(" / ") if messages.any?
      end

      result.add_warning(line: row.line, message: warning) if warning

      if action == :created
        result.add_created(line: row.line, label: label, record: listing)
      else
        result.add_updated(line: row.line, label: label, record: listing)
      end
    end

    def listing_attributes(row)
      title = require_title(row)
      {
        title: title,
        description: row["description"].to_s,
        skill_markdown: row["skill_markdown"].to_s,
        price_cents: price_cents(row),
        currency: currency(row),
        author: author(row),
        category: category(row),
        listing_shape: listing_shape(row),
        open: open?(row)
      }
    end

    def require_title(row)
      title = row["title"]
      raise RowError, "title が空です" if title.nil?
      if title.length < TITLE_MIN_LENGTH || title.length > TITLE_MAX_LENGTH
        raise RowError, "title は #{TITLE_MIN_LENGTH}〜#{TITLE_MAX_LENGTH} 文字で指定してください（#{title.length} 文字）"
      end

      title
    end

    def price_cents(row)
      value = row["price_cents"]
      raise RowError, "price_cents が空です（1 以上の整数を指定してください）" if value.nil?

      cents = Coercion.integer(value)
      raise RowError, "price_cents は 1 以上の整数で指定してください（#{value}）" if cents.nil? || cents <= 0

      cents
    end

    def currency(row)
      value = (row["currency"] || DEFAULT_CURRENCY).upcase
      raise RowError, "currency は 3 文字の通貨コードで指定してください（#{row['currency']}）" unless value.match?(CURRENCY_FORMAT)

      value
    end

    def open?(row)
      return true if row["open"].nil?

      parsed = Coercion.boolean(row["open"])
      raise RowError, "open は true / false（または 1 / 0）で指定してください（#{row['open']}）" if parsed.nil?

      parsed
    end

    def author(row)
      email = row["author_email"].to_s.strip.downcase
      raise RowError, "author_email が空です" if email.empty?

      person = person_by_email(email)
      raise RowError, "author_email '#{email}' のユーザーが見つかりません（先に import:users を実行してください）" if person.nil?

      person
    end

    def person_by_email(email)
      email_record = Email.where(address: email, community_id: community.id).order(:id).first
      return email_record.person if email_record&.person && !email_record.person.deleted

      Email.where(address: email).order(:id).to_a.detect do |record|
        record.person && !record.person.deleted && record.person.community_id == community.id
      end&.person
    end

    def category(row)
      value = row["category"]
      return default_category if value.nil?

      found = community.categories.find_by_url_or_id(value)
      raise RowError, "category '#{value}' が見つかりません（url スラッグまたは id を指定してください）" if found.nil?

      found
    end

    # 既定カテゴリ = 「システム用カテゴリ」を除く先頭のメインカテゴリ。
    def default_category
      @default_category ||= begin
        main = community.categories.where(parent_id: nil).to_a
                        .reject { |category| SYSTEM_CATEGORY_URLS.include?(category.url.to_s) }
                        .first
        raise RowError, "既定のカテゴリが決められません（category 列で指定してください）" if main.nil?

        main
      end
    end

    def listing_shape(row)
      value = row["listing_shape"]
      shapes = community.shapes

      if value
        found = shapes.find { |shape| shape.name == value } || shapes.find { |shape| shape.id.to_s == value }
        raise RowError, "listing_shape '#{value}' が見つかりません（name または id を指定してください）" if found.nil?

        return found
      end

      default_shape(shapes)
    end

    def default_shape(shapes)
      shape = shapes.find { |candidate| candidate.name == ListingShape::DEFAULT_BASENAME } || shapes.first
      raise RowError, "コミュニティに出品タイプ（listing_shape）がありません" if shape.nil?

      shape
    end

    def skill_markdown_warning(row)
      return nil unless row["skill_markdown"].nil?

      "skill_markdown が空です（システムプロンプトなしの出品になります）"
    end

    def find_listing(title, person)
      Listing.where(community_id: community.id, author_id: person.id, title: title, deleted: false).order(:id).first
    end
  end
end
