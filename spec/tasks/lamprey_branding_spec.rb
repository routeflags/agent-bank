# frozen_string_literal: true

require 'rails_helper'

# 消費者向け表記「楽市楽問」統一タスクのスペック（Issue #38）。
RSpec.describe "lamprey:branding:unify_service_name", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lamprey:branding:unify_service_name")
  end

  def run_task(community_ref = nil)
    task = Rake::Task["lamprey:branding:unify_service_name"]
    task.reenable
    community_ref ? task.invoke(community_ref.to_s) : task.invoke
  end

  context "community_id 明示指定の場合" do
    let(:community) { FactoryBot.create(:community) }

    it "ja 行を作成し名称を楽市楽問にする" do
      expect(community.community_customizations.where(locale: "ja")).to be_empty

      expect { run_task(community.id) }
        .to output(/更新: community_id=#{community.id}.*name/).to_stdout

      ja = community.reload.community_customizations.find_by(locale: "ja")
      expect(ja.name).to eq("楽市楽問")
    end

    it "利用規約の日本文面を投入し英語デフォルトが出ない" do
      run_task(community.id)
      ja = community.reload.community_customizations.find_by(locale: "ja")
      expect(ja.terms_page_content).to include("楽市楽問 利用規約")
      expect(ja.terms_page_content).not_to include("Terms of Service for")
    end

    it "en 行には触れない" do
      en_before = community.community_customizations.find_by(locale: "en")
      expect {
        run_task(community.id)
      }.not_to change { en_before.reload.updated_at }
    end

    it "2回目は変更なし（冪等）" do
      run_task(community.id)
      expect { run_task(community.id) }
        .to output(/変更なし/).to_stdout
      expect {
        run_task(community.id)
      }.not_to change { community.reload.community_customizations.find_by(locale: "ja").updated_at }
    end

    it "独自設定済みの名称・規約は上書きしない" do
      community.community_customizations.create!(
        locale: "ja", name: "オーナー独自名", terms_page_content: "<p>独自規約</p>"
      )
      run_task(community.id)
      ja = community.reload.community_customizations.find_by(locale: "ja")
      expect(ja.name).to eq("オーナー独自名")
      expect(ja.terms_page_content).to eq("<p>独自規約</p>")
    end

    it "存在しない community_id なら中断する" do
      expect { run_task("-1") }.to raise_error(SystemExit)
    end
  end

  context "ident 解決の場合" do
    it "ident agent-bank の community を対象にする" do
      community = FactoryBot.create(:community, ident: "agent-bank")
      expect { run_task }
        .to change { community.reload.community_customizations.where(locale: "ja").count }.by(1)
    end

    it "ident が一致しない community には触れない" do
      other = FactoryBot.create(:community, ident: "other-market")
      expect { run_task rescue SystemExit }.not_to change {
        other.reload.community_customizations.where(locale: "ja").count
      }
    end
  end
end
