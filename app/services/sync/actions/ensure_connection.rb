# frozen_string_literal: true

module Sync
  module Actions
    # Ensures a connection to a relay is established
    # Handles reconnection, new connection creation, and waiting for connection
    class EnsureConnection < BaseService
      option :relay_url, type: Types::RelayUrl
      option :timeout, type: Types::Integer, default: -> { 30 }

      def call
        conn = RelaySync.manager.connection_for(relay_url)

        if conn&.connected?
          Rails.logger.debug "[EnsureConnection] Reusing existing connection to #{relay_url}"
          return Success(connection: conn)
        elsif conn && !conn.connected?
          Rails.logger.info "[EnsureConnection] Reconnecting to #{relay_url} (state: #{conn.state})"
          conn.connect
        else
          Rails.logger.info "[EnsureConnection] Creating new connection to #{relay_url}"
          RelaySync.manager.add_connection(relay_url)
        end

        wait_for_connection
        Success(connection: RelaySync.manager.connection_for(relay_url))
      end

      private

      def wait_for_connection
        deadline = Time.now + timeout

        loop do
          conn = RelaySync.manager.connection_for(relay_url)
          if conn&.connected?
            Rails.logger.debug "[EnsureConnection] Connected to #{relay_url}"
            return
          end

          if Time.now > deadline
            Rails.logger.error "[EnsureConnection] Timeout - state: #{conn&.state || 'no connection'}"
            raise RelaySync::ConnectionError, "Timeout connecting to #{relay_url}"
          end

          sleep 0.5
        end
      end
    end
  end
end
