# frozen_string_literal: true

# Issue #138: 出品の既定を「チャットで動くペルソナ」に合わせる。
#
# `default_run_mode` の DB 既定が `download` だったため、CSV/シード由来の出品は
# 出品ページに ChatPanel が出ず、取引メッセージ導線へ流れていた。
# 画面からの出品（ListingFormViewUtils）と同じ `run_online` を既定にする。
class ChangeDefaultRunModeToRunOnline < ActiveRecord::Migration[8.1]
  def up
    change_column_default :listings, :default_run_mode, from: "download", to: "run_online"
  end

  def down
    change_column_default :listings, :default_run_mode, from: "run_online", to: "download"
  end
end
