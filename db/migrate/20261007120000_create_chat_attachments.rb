# frozen_string_literal: true

class CreateChatAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_attachments do |t|
      t.bigint :chat_session_id, null: false
      t.string :person_id, null: false
      t.string :image_file_name
      t.string :image_content_type
      t.integer :image_file_size
      t.datetime :image_updated_at
      t.timestamps
    end

    add_foreign_key :chat_attachments, :chat_sessions
    add_foreign_key :chat_attachments, :people
  end
end
