class CreateAiModels < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_models do |t|
      t.references :ai_provider, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :model_id, null: false
      t.integer :max_tokens, default: 4096
      t.integer :context_window
      t.decimal :cost_per_1k_input, precision: 10, scale: 6
      t.decimal :cost_per_1k_output, precision: 10, scale: 6
      t.boolean :supports_streaming, default: true
      t.boolean :supports_vision, default: false
      t.boolean :supports_tools, default: false
      t.boolean :is_active, default: true
      t.timestamps
    end

    add_index :ai_models, [:ai_provider_id, :slug], unique: true
    add_index :ai_models, [:ai_provider_id, :model_id], unique: true
  end
end
