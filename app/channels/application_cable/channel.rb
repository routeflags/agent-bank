# frozen_string_literal: true

# Base channel class for Action Cable.
#
# Provides a common interface for all channels in the application.
# Subclasses automatically inherit the current_user reference from
# the authenticated Connection.
module ApplicationCable
  class Channel < ActionCable::Channel::Base

    protected

    # Expose current_user from the authenticated Connection to subclasses.
    def current_user
      connection.current_user
    end
  end
end
