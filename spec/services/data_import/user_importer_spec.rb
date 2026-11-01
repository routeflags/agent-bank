# frozen_string_literal: true

require "rails_helper"
require "csv"
require "fileutils"
require "tmpdir"

# users.csv インポートの振る舞い（Issue #135）。
#
# 観点:
#   * ドライラン（既定）は一切書き込まない
#   * COMMIT=1 で Person + Email（confirmed）が作られる
#   * 同じ CSV を 2 回流しても重複しない（冪等）
#   * 不正行は行番号つきでエラーになり、他の正常行は投入される
RSpec.describe DataImport::UserImporter do
  let!(:community) { FactoryBot.create(:community) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:csv_path) { File.join(tmpdir, "users.csv") }
  let(:headers) { %w[email given_name family_name display_name username locale is_admin password] }

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
    row = ["sample.taro@example.com", "太郎", "山田", nil, nil, nil, nil, nil]
    overrides.each { |index, value| row[index] = value }
    row
  end

  describe "ドライラン（既定）" do
    it "書き込みをせず、作成予定だけを返す" do
      write_csv([valid_row])

      result = nil
      expect { result = import }.not_to(change { [Person.count, Email.count] })

      expect(result.created.size).to eq 1
      expect(result.errors).to be_empty
      expect(result.created.first.line).to eq 2
      expect(result.created.first.label).to eq "sample.taro@example.com"
    end
  end

  describe "COMMIT=1（実書き込み）" do
    it "Person と confirmed 済みの Email を作り、既定値を埋める" do
      write_csv([valid_row])

      result = import(commit: true)
      expect(result.created.size).to eq 1

      person = Person.find_by(username: "sample_taro")
      expect(person).to be_present
      expect(person.community_id).to eq community.id
      expect(person.given_name).to eq "太郎"
      expect(person.family_name).to eq "山田"
      expect(person.display_name).to eq "山田 太郎"
      expect(person.locale).to eq "ja"
      expect(person.is_admin).to eq 0
      expect(person.encrypted_password.present?).to be true

      email = Email.find_by(person_id: person.id)
      expect(email.address).to eq "sample.taro@example.com"
      expect(email.community_id).to eq community.id
      expect(email.confirmed_at).to be_present
    end

    it "password を指定するとそのパスワードでログインできる" do
      write_csv([valid_row(7 => "Passw0rd!")])

      import(commit: true)

      person = Person.find_by(username: "sample_taro")
      expect(person.valid_password?("Passw0rd!")).to be true
    end

    it "password を結果に含めない" do
      write_csv([valid_row(7 => "Secret123!")])

      result = import(commit: true)
      printed = (result.created + result.updated + result.skipped + result.errors + result.warnings).map(&:to_s).join("\n")
      expect(printed).not_to include("Secret123!")
    end

    it "同じ CSV の 2 回目は skipped になり件数が増えない" do
      write_csv([valid_row])
      import(commit: true)

      result = nil
      expect { result = import(commit: true) }.not_to(change { [Person.count, Email.count] })

      expect(result.created).to be_empty
      expect(result.skipped.size).to eq 1
      expect(result.skipped.first.reason).to include("既に存在")
    end

    it "ON_CONFLICT=update でプロフィールを更新する" do
      write_csv([valid_row])
      import(commit: true)

      write_csv([["sample.taro@example.com", "次郎", "山田", "山田 次郎", nil, "en", "true", nil]])
      result = import(commit: true, on_conflict: "update")

      expect(result.updated.size).to eq 1
      person = Person.find_by(username: "sample_taro")
      expect(person.given_name).to eq "次郎"
      expect(person.display_name).to eq "山田 次郎"
      expect(person.locale).to eq "en"
      expect(person.is_admin).to eq 1
    end

    it "不正行は行番号つきでエラーになり、他の正常行は投入される" do
      write_csv([
                  ["not-an-email", "太郎", "山田", nil, nil, nil, nil, nil],
                  ["hanako.sato@example.com", "花子", "佐藤", nil, nil, nil, nil, nil]
                ])

      result = import(commit: true)

      expect(result.errors.size).to eq 1
      expect(result.errors.first.line).to eq 2
      expect(result.errors.first.message).to include("email の形式")
      expect(result.created.size).to eq 1
      expect(Person.where(username: "hanako_sato", community_id: community.id).count).to eq 1
    end
  end

  describe "username" do
    it "email のローカル部から生成する" do
      write_csv([valid_row])
      import(commit: true)
      expect(Person.where(username: "sample_taro", community_id: community.id).count).to eq 1
    end

    it "衝突したら接尾辞を付ける" do
      FactoryBot.create(:person, community_id: community.id, username: "sample_taro")
      write_csv([valid_row])

      import(commit: true)

      expect(Person.where(username: "sample_taro_1", community_id: community.id).count).to eq 1
    end

    it "明示指定の書式不正は行エラーにする" do
      write_csv([valid_row(4 => "Taro Yamada")])

      result = import

      expect(result.errors.size).to eq 1
      expect(result.errors.first.message).to include("username")
    end
  end

  describe "値の検証" do
    it "password が 4 文字未満なら行エラー" do
      write_csv([valid_row(7 => "abc")])
      expect(import.errors.first.message).to include("password")
    end

    it "is_admin が真偽値でなければ行エラー" do
      write_csv([valid_row(6 => "maybe")])
      expect(import.errors.first.message).to include("is_admin")
    end

    it "given_name が空なら行エラー" do
      write_csv([valid_row(1 => nil)])
      result = import
      expect(result.errors.first.line).to eq 2
      expect(result.errors.first.message).to include("given_name")
    end

    it "氏名が 30 文字を超えると行エラー" do
      write_csv([valid_row(1 => "あ" * 31)])
      expect(import.errors.first.message).to include("given_name")
    end
  end

  describe "CSV の読み込み" do
    it "BOM・大文字ヘッダー・前後の空白を吸収する" do
      File.binwrite(
        csv_path,
        "\xEF\xBB\xBF Email , Given_Name , Family_Name \n sample.taro@example.com , 太郎 , 山田 \n"
      )

      result = import

      expect(result.created.size).to eq 1
      expect(result.errors).to be_empty
    end

    it "必須列が無いと InvalidFileError" do
      write_csv([], header: %w[email given_name])

      expect { import }.to raise_error(DataImport::CsvReader::InvalidFileError, /family_name/)
    end

    it "未知の列は ignored_columns で返し、処理は続く" do
      write_csv([valid_row + ["余分"]], header: headers + ["unknown_column"])

      result = import

      expect(result.ignored_columns).to eq ["unknown_column"]
      expect(result.created.size).to eq 1
    end

    it "全列が空の行は無視する" do
      write_csv([valid_row, [nil, nil, nil, nil, nil, nil, nil, nil]])

      result = import

      expect(result.created.size).to eq 1
      expect(result.errors).to be_empty
    end

    it "存在しないファイルは InvalidFileError" do
      FileUtils.rm_f(csv_path)

      expect { import }.to raise_error(DataImport::CsvReader::InvalidFileError, /ファイルが見つかりません/)
    end
  end

  describe "オプション" do
    it "不正な ON_CONFLICT は ArgumentError" do
      write_csv([valid_row])

      expect { import(on_conflict: "replace") }.to raise_error(ArgumentError, /ON_CONFLICT/)
    end
  end
end
