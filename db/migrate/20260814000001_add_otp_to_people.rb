class AddOtpToPeople < ActiveRecord::Migration[6.1]
  def change
    add_column :people, :otp_secret, :string
    add_column :people, :otp_required_for_login, :boolean, default: false
  end
end
