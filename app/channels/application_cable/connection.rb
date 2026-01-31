# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # No authentication required for ActionCable connections
    # The Stats dashboard handles its own session-based auth
  end
end
