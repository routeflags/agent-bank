class AddCapafyFieldsToListings < ActiveRecord::Migration[6.1]
  def change
    add_column :listings, :short_description, :text
    add_column :listings, :supported_run_modes, :json
    add_column :listings, :default_run_mode, :string, default: 'download'
    add_column :listings, :external_apis, :json
    add_column :listings, :version_number, :string
    add_column :listings, :publisher_name, :string
    add_column :listings, :total_sold, :integer, default: 0
    add_column :listings, :avg_rating, :float, default: 0.0
  end
end
