class AddTitleToChatSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_sessions, :title, :string, limit: 100
  end
end
