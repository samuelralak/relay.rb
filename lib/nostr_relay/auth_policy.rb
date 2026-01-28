# frozen_string_literal: true

module NostrRelay
  # Centralized authentication policy for NIP-42 and NIP-70.
  # Determines when authentication is required for events and subscriptions.
  module AuthPolicy
    module_function

    # Check if an EVENT submission requires authentication.
    # @param event_data [Hash] The event data
    # @param connection [Connection] The WebSocket connection
    # @return [Boolean] True if authentication is required
    def event_requires_auth?(event_data, connection)
      # Global auth requirement
      return true if Config.auth_required?

      # NIP-70: Protected events ALWAYS require auth
      # Default behavior: reject ["-"] tagged events unless auth enabled AND author authenticated
      if protected_event?(event_data)
        return true unless Config.auth_enabled? && author_authenticated?(event_data, connection)
      end

      false
    end

    # NIP-70: Check if event has the protected "-" tag.
    # Protected events can only be published by their author.
    # @param event_data [Hash] The event data
    # @return [Boolean] True if event is protected
    def protected_event?(event_data)
      tags = event_data["tags"] || event_data[:tags] || []
      tags.any? { |t| t.is_a?(Array) && t[0] == "-" }
    end

    # Check if the event's author is authenticated on this connection.
    # @param event_data [Hash] The event data
    # @param connection [Connection] The WebSocket connection
    # @return [Boolean] True if author is authenticated
    def author_authenticated?(event_data, connection)
      pubkey = event_data["pubkey"] || event_data[:pubkey]
      connection.authenticated?(pubkey)
    end

    # Build the appropriate error message for authentication failures.
    # NIP-70: Use auth-required first, then restricted after failed auth.
    # @param event_data [Hash] The event data
    # @param connection [Connection] The WebSocket connection
    # @return [String] The error message with appropriate prefix
    def auth_error_message(event_data, connection)
      if protected_event?(event_data)
        if connection.authenticated?
          # User authenticated but with wrong pubkey
          Messages::Prefix.build(Messages::Prefix::RESTRICTED, "only the author can publish this protected event")
        else
          # User not authenticated at all
          Messages::Prefix.build(Messages::Prefix::AUTH_REQUIRED, "this event may only be published by its author")
        end
      else
        Messages::Prefix.build(Messages::Prefix::AUTH_REQUIRED, "authentication required")
      end
    end
  end
end
