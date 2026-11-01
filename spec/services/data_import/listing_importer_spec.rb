# frozen_string_literal: true

require "rails_helper"
require "csv"
require "fileutils"
require "tmpdir"

# listings.csv インポートの振る舞い（Issue #135）。
#
# 観点:
#   * ドライラン（既定）は一切書き込まない
#   * COMMIT=1 で `Listing.currently_open`（= /browse の対象）に載る出品が作られる
#   * 同じ CSV を 2 回流しても重複しない（冪等）
#   * 不正行は行番号つきでエラーになり、他の正常行は投入される
RSpec.describe DataImport::ListingImporter do
  let(:community) { FactoryBot.create(:community) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:csv_path) { File.join(tmpdir, "listings.csv") }
  let(:headers) { %w[title price_cents author_email description skill_markdown category open currency] }

  let!(:transaction_process) { FactoryBot.create(:transaction_process, community_id: community.id) }
  let!(:default_shape) do
    FactoryBot.create(:listing_shape,
                      community_id: community.id,
                      transaction_process_id: transaction_process.id,
                      name: ListingShape::DEFAULT_BASENAME)
  end
  let!(:category) { FactoryBot.create(:category, community_id: community.id, url: "cat-a", sort_priority: 0) }
  let(:author) { FactoryBot.create(:person, community_id: community.id, username: "persona_author") }
  let!(:author_email) do
    FactoryBot.create(:email, person: author, community_id: community.id, address: "author@example.com")
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def write_csv(rows, header: nil)
    CSV.open(csv_path, "w") do |csv|
      csv << (header || headers)
      rows.each { |row| csv << row }
    end
    csv_path
  end

  def import(commit: false, on_conflict: "skip")
    described_class.import(csv_path, community: community, commit: commit, on_conflict: on_conflict)
  end

  def valid_row(overrides = {})
    row = ["サンプル — 翻訳ペルソナ", "1200", "author@example.com", "説明文",
           "あなたは翻訳ペルソナです。", category.id.to_s, "true", nil]
    overrides.each { |index, value| row[index] = value }
    row
  end

  describe "ドライラン（既定）" do
    it "書き込みをせず、作成予定だけを返す" do
      write_csv([valid_row])

      result = nil
      expect { result = import }.not_to change(Listing, :count)

      expect(result.created.size).to eq 1
      expect(result.errors).to be_empty
      expect(result.created.first.line).to eq 2
    end
  end

  describe "COMMIT=1（実書き込み）" do
    it "出品を作り、既定値と一覧条件（currently_open）を満たす" do
      write_csv([valid_row])

      result = import(commit: true)
      expect(result.created.size).to eq 1

      listing = Listing.find_by(title: "サンプル — 翻訳ペルソナ")
      expect(listing).to be_present
      expect(listing.community_id).to eq community.id
      expect(listing.author_id).to eq author.id
      expect(listing.price_cents).to eq 1200
      expect(listing.currency).to eq "JPY"
      expect(listing.open).to be true
      expect(listing.deleted).to be false
      expect(listing.state).to eq "approved"
      expect(listing.category_id).to eq category.id
      expect(listing.listing_shape_id).to eq default_shape.id
      expect(listing.description).to eq "説明文"
      expect(listing.skill_markdown).to eq "あなたは翻訳ペルソナです。"

      browsable = Listing.currently_open.where(community_id: community.id).pluck(:id)
      expect(browsable).to include(listing.id)
    end

    it "open: false の行は一覧条件に載らない" do
      write_csv([valid_row(6 => "false")])

      import(commit: true)

      listing = Listing.find_by(title: "サンプル — 翻訳ペルソナ")
      expect(listing.open).to be false
      expect(Listing.currently_open.where(community_id: community.id).pluck(:id)).not_to include(listing.id)
    end

    it "category 空欄ならシステム用以外の先頭メインカテゴリを使う" do
      write_csv([valid_row(5 => nil)])

      import(commit: true)

      expect(Listing.find_by(title: "サンプル — 翻訳ペルソナ").category_id).to eq category.id
    end

    it "category は url スラッグでも指定できる" do
      category.update_column(:url, "cat-a")
      write_csv([valid_row(5 => "cat-a")])

      import(commit: true)

      expect(Listing.find_by(title: "サンプル — 翻訳ペルソナ").category_id).to eq category.id
    end

    it "skill_markdown が空なら警告を出しつつ作成する" do
      write_csv([valid_row(4 => nil)])

      result = import(commit: true)

      expect(result.created.size).to eq 1
      expect(result.warnings.size).to eq 1
      expect(result.warnings.first.line).to eq 2
      expect(result.warnings.first.message).to include("skill_markdown")
    end

    it "同じ CSV の 2 回目は skipped になり件数が増えない" do
      write_csv([valid_row])
      import(commit: true)

      result = nil
      expect { result = import(commit: true) }.not_to change(Listing, :count)

      expect(result.created).to be_empty
      expect(result.skipped.size).to eq 1
      expect(result.skipped.first.reason).to include("既に存在")
    end

    it "ON_CONFLICT=update で価格と説明を更新する" do
      write_csv([valid_row])
      import(commit: true)

      write_csv([valid_row(1 => "2000", 3 => "新しい説明")])
      result = import(commit: true, on_conflict: "update")

      expect(result.updated.size).to eq 1
      listing = Listing.find_by(title: "サンプル — 翻訳ペルソナ")
      expect(listing.price_cents).to eq 2000
      expect(listing.description).to eq "新しい説明"
    end

    it "不正行は行番号つきでエラーになり、他の正常行は投入される" do
      write_csv([
                  valid_row(1 => "0"),
                  valid_row(2 => "unknown@example.com"),
                  valid_row
                ])

      result = import(commit: true)

      expect(result.errors.map(&:line)).to eq [2, 3]
      expect(result.errors.first.message).to include("price_cents")
      expect(result.errors.last.message).to include("author_email")
      expect(result.created.size).to eq 1
      expect(Listing.where(title: "サンプル — 翻訳ペルソナ").count).to eq 1
    end

    it "deleted の同タイトル出品は重複とみなさない" do
      FactoryBot.create(:listing,
                        community_id: community.id,
                        author: author,
                        title: "サンプル — 翻訳ペルソナ",
                        deleted: true)
      write_csv([valid_row])

      result = import(commit: true)

      expect(result.created.size).to eq 1
      expect(Listing.where(title: "サンプル — 翻訳ペルソナ", deleted: false).count).to eq 1
    end
  end

  describe "値の検証" do
    it "title が短すぎると行エラー" do
      write_csv([valid_row(0 => "あ")])
      expect(import.errors.first.message).to include("title")
    end

    it "title が 65 文字を超えると行エラー" do
      write_csv([valid_row(0 => "あ" * 66)])
      expect(import.errors.first.message).to include("title")
    end

    it "price_cents が整数でないと行エラー" do
      write_csv([valid_row(1 => "1,000")])
      expect(import.errors.first.message).to include("price_cents")
    end

    it "category が見つからないと行エラー" do
      write_csv([valid_row(5 => "no-such-category")])
      expect(import.errors.first.message).to include("category")
    end

    it "currency が 3 文字でないと行エラー" do
      write_csv([valid_row(7 => "JPYY")])
      expect(import.errors.first.message).to include("currency")
    end

    it "open が真偽値でなければ行エラー" do
      write_csv([valid_row(6 => "maybe")])
      expect(import.errors.first.message).to include("open")
    end
  end

  describe "CSV の読み込み" do
    it "必須列が無いと InvalidFileError" do
      write_csv([], header: %w[title price_cents])

      expect { import }.to raise_error(DataImport::CsvReader::InvalidFileError, /author_email/)
    end
  end
end
