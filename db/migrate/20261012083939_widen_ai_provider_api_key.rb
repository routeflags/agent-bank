class WidenAiProviderAPIKey < ActiveRecord::Migration[8.1]
  def change
    change_column :ai_providers, :api_key_encrypted, :text
  end
end
