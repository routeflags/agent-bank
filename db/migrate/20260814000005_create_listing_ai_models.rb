class CreateListingAiModels < ActiveRecord::Migration[6.1]
  def change
    create_table :listing_ai_models do |t|
      t.integer :listing_id, null: false
      t.references :ai_model, null: false, foreign_key: true
      t.boolean :is_default, default: false
      t.timestamps
    end

    add_index :listing_ai_models, [:listing_id, :ai_model_id], unique: true
    add_index :listing_ai_models, :listing_id,
      unique: true,
      name: 'index_listing_ai_models_on_listing_id_default_unique',
      where: "is_default = 1"
    add_foreign_key :listing_ai_models, :listings
  end
end
