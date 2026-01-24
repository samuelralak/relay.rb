# frozen_string_literal: true

module Sync
  # Provides connection validation and access for sync services.
  # Include this in services that need to communicate with relays.
  module Connectionable
    extend ActiveSupport::Concern

    private

    # Validates that a connection exists and is active.
    # Raises RelaySync::ConnectionError if not connected.
    def validate_connection!
      raise RelaySync::ConnectionError, "Not connected to #{relay_url}" unless connection&.connected?
    end

    # Returns the memoized connection for the relay_url.
    # Assumes the including class has a `relay_url` method/option.
    def connection
      @connection ||= RelaySync.manager.connection_for(relay_url)
    end
  end
end
