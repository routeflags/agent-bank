# == Schema Information
#
# Table name: chat_attachments
#
#  id                 :integer          not null, primary key
#  chat_session_id    :integer          not null
#  person_id          :string(255)      not null
#  image_file_name    :string(255)
#  image_content_type :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  fk_rails_617d1d368c  (chat_session_id)
#  fk_rails_f9af74d956  (person_id)
#

# frozen_string_literal: true

# Image attachment for chat messages (DESIGN.md §15 composer 📎 control).
# Uploaded via API::V1::ChatAttachmentsController, referenced from
# ChatMessage#metadata["attachment_id"].
class ChatAttachment < ApplicationRecord
  IMAGE_CONTENT_TYPE = %w[image/jpeg image/png image/gif image/webp].freeze

  belongs_to :chat_session
  belongs_to :person

  has_attached_file :image,
                    styles: { medium: "600x600>" },
                    convert_options: { all: "-strip" }

  validates_attachment_content_type :image, content_type: IMAGE_CONTENT_TYPE
  validates_attachment_size :image, less_than: 5.megabytes
end
