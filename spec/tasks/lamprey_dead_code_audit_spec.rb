# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# デッドコード監査 Rake タスクのスペック（Issue #60 Phase B）。
#
# モジュール単体（小さな fixture ツリーで検証）と、実リポジトリに対する
# タスク実行（Phase A で消した列が出力に出てこないこと）の両面を担保する。
# 監査は読み取り専用（structure.sql とコードの読み取りだけ）のため、
# DB への書き込みは行わない。
RSpec.describe "lamprey:audit:dead_code", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lamprey:audit:dead_code")
  end

  def write_file(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def fixture_root
    root = Dir.mktmpdir("dead_code_audit")
    write_file(root, "db/structure.sql", <<~SQL)
      CREATE TABLE `widgets` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `name` varchar(255) DEFAULT NULL,
        `dead_col` varchar(255) DEFAULT NULL,
        PRIMARY KEY (`id`),
        KEY `index_widgets_on_name` (`name`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
      CREATE TABLE `ghost_table` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        PRIMARY KEY (`id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
      CREATE TABLE `delayed_jobs` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `locked_by` varchar(255) DEFAULT NULL,
        PRIMARY KEY (`id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL
    root
  end

  describe "LampreyDeadCodeAudit" do
    it "注釈ブロックのみの言及は参照に数えない" do
      root = fixture_root
      write_file(root, "app/models/widget.rb", <<~'RUBY')
        # == Schema Information
        #
        # Table name: widgets
        #
        #  id       :integer  not null, primary key
        #  name     :string
        #  dead_col :string
        #
        class Widget < ApplicationRecord
          validates :name, presence: true

          def label
            "#{id}:#{name}"
          end
        end
      RUBY

      result = LampreyDeadCodeAudit.run(root: root, out: StringIO.new)

      expect(result.unused_columns).to eq(["widgets.dead_col"])
    end

    it "フレームワーク管理テーブルとその列は監査しない" do
      root = fixture_root
      write_file(root, "app/models/widget.rb", "class Widget < ApplicationRecord; end\n")

      result = LampreyDeadCodeAudit.run(root: root, out: StringIO.new)

      expect(result.unused_tables).not_to include("delayed_jobs")
      expect(result.unused_columns).not_to include("delayed_jobs.locked_by")
    end

    it "モデルも参照も無いテーブルを報告する" do
      root = fixture_root
      write_file(root, "app/models/widget.rb", "class Widget < ApplicationRecord; end\n")

      result = LampreyDeadCodeAudit.run(root: root, out: StringIO.new)

      expect(result.unused_tables).to eq(["ghost_table"])
    end

    it "複数形・スネークケースの参照を拾う（has_many 等の Rails 流儀）" do
      root = fixture_root
      write_file(root, "app/models/chat_attachment.rb", "class ChatAttachment < ApplicationRecord; end\n")
      write_file(root, "app/models/chat_session.rb", <<~RUBY)
        class ChatSession < ApplicationRecord
          has_many :chat_attachments, dependent: :destroy
        end
      RUBY
      write_file(root, "app/controllers/chat_sessions_controller.rb", <<~RUBY)
        class ChatSessionsController < ApplicationController
          def show
            @session = ChatSession.find(params[:id])
          end
        end
      RUBY

      result = LampreyDeadCodeAudit.run(root: root, out: StringIO.new)

      expect(result.unused_classes).not_to include("ChatAttachment")
      expect(result.unused_classes).not_to include("ChatSession")
    end

    it "どこからも参照されないクラスを報告する" do
      root = fixture_root
      write_file(root, "app/models/widget.rb", "class Widget < ApplicationRecord; end\n")
      write_file(root, "app/services/widget_service.rb", "class WidgetService\n  def call\n    Widget.all\n  end\nend\n")
      write_file(root, "app/jobs/forgotten_job.rb", "class ForgottenJob < Struct.new(:id); end\n")

      result = LampreyDeadCodeAudit.run(root: root, out: StringIO.new)

      expect(result.unused_classes).to include("ForgottenJob", "WidgetService")
      expect(result.unused_classes).not_to include("Widget")
    end

    it "helpers 配下のクラスは監査対象にしないが参照元としては数える" do
      root = fixture_root
      write_file(root, "app/models/widget.rb", "class Widget < ApplicationRecord; end\n")
      write_file(root, "app/helpers/magic_helper.rb", <<~RUBY)
        module MagicHelper
          def magic
            Widget.all
          end
        end
      RUBY

      result = LampreyDeadCodeAudit.run(root: root, out: StringIO.new)

      expect(result.unused_classes).not_to include("MagicHelper")
      expect(result.unused_classes).not_to include("Widget")
    end
  end

  describe "実リポジトリに対する実行" do
    def run_task_output
      task = Rake::Task["lamprey:audit:dead_code"]
      task.reenable
      original = $stdout
      $stdout = StringIO.new
      task.invoke
      $stdout.string
    ensure
      $stdout = original
    end

    it "実行でき、Phase A で消した列・テーブルが出力に出てこない" do
      output = run_task_output

      expect(output).to include("デッドコード監査レポート")
      expect(output).to include("参照ゼロの列")
      expect(output).to include("参照ゼロのテーブル")
      expect(output).to include("参照ゼロクラス")
      %w[publisher_name version_number otp_required_for_login plan_type checkout_accounts].each do |token|
        expect(output).not_to include(token)
      end
    end
  end
end
