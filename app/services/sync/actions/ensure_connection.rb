# frozen_string_literal: true

module Sync
  module Actions
    # Ensures a connection to a relay is established
    # Handles reconnection, new connection creation, and waiting for connection
    class EnsureConnection < BaseService
      include Loggable

      option :relay_url, type: Types::RelayUrl
      option :timeout, type: Types::Integer, default: -> { 30 }

      def call
        conn = RelaySync.manager.connection_for(relay_url)

        if conn&.connected?
          logger.debug("Reusing existing connection", relay_url:)
          return Success(connection: conn)
        elsif conn && !conn.connected?
          logger.info "Reconnecting", relay_url:, state: conn.state
          conn.connect
        else
          logger.info("Creating new connection", relay_url:)
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
            logger.debug("Connected", relay_url:)
            return
          end

          if Time.now > deadline
            logger.error "Timeout", state: conn&.state || "no connection"
            raise RelaySync::ConnectionError, "Timeout connecting to #{relay_url}"
          end

          sleep 0.5
        end
      end
    end
  end
end
