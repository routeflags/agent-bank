class CreateAiProviders < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_providers do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :api_key_encrypted
      t.string :base_url
      t.json :config
      t.boolean :is_active, default: true
      t.timestamps
    end

    add_index :ai_providers, :slug, unique: true
  end
end
