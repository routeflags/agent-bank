# frozen_string_literal: true

# Base connection class for Action Cable.
#
# Authenticates users via Warden (Devise) session cookie.
# Each connection is identified by a unique uuid and carries
# a reference to the authenticated Person.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :connection_id

    def connect
      self.connection_id = SecureRandom.uuid
      self.current_user = find_current_user
      reject_unauthorized_connection unless current_user
    end

    private

    # Warden is the Rack middleware that Devise uses for session management.
    # In Action Cable requests, Devise helpers are not available, so we
    # access Warden directly to retrieve the authenticated user.
    def find_current_user
      env['warden'].user
    end
  end
end
