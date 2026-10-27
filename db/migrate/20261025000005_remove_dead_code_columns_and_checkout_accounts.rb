# frozen_string_literal: true

# Issue #60 Phase A: 参照ゼロの列・テーブルを撤去する。
#
# - listings.publisher_name / listings.version_number:
#   参照は Listing#persona_card のみ（本 Issue で同時に除外）。
#   値のある6件は表示・利用箇所が無いため失ってよい（Issue #60 に記録）。
# - people.otp_required_for_login: 参照0件。true の行は0件。
# - contact_requests.plan_type: 参照0件。値のある行は0件。
# - checkout_accounts テーブル: Stripe Connect の残骸。モデル・参照なし、0行。
# いずれもデータ移行は行わない。
class RemoveDeadCodeColumnsAndCheckoutAccounts < ActiveRecord::Migration[8.1]
  def up
    change_table :listings, bulk: true do |t|
      t.remove :publisher_name, type: :string
      t.remove :version_number, type: :string
    end
    remove_column :people, :otp_required_for_login, :boolean
    remove_column :contact_requests, :plan_type, :string
    drop_table :checkout_accounts
  end

  def down
    change_table :listings, bulk: true do |t|
      t.string :publisher_name
      t.string :version_number
    end
    add_column :people, :otp_required_for_login, :boolean, default: false
    add_column :contact_requests, :plan_type, :string
    create_table :checkout_accounts do |t|
      t.string :company_id_or_personal_id
      t.string :merchant_id, null: false
      t.string :merchant_key, null: false
      t.string :person_id, null: false
      t.timestamps null: false
    end
  end
end
