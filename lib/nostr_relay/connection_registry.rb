# frozen_string_literal: true

require "concurrent"

module NostrRelay
  # Thread-safe registry for WebSocket connections.
  # Extracted from Subscriptions to separate connection management from subscription logic.
  module ConnectionRegistry
    class << self
      def connections
        @connections ||= Concurrent::Hash.new
      end

      # Register a new connection
      # @param connection [Connection] WebSocket connection
      def register(connection)
        connections[connection.id] = connection
      end

      # Unregister a connection by ID
      # @param connection_id [String] connection ID
      # @return [Connection, nil] removed connection or nil
      def unregister(connection_id)
        connections.delete(connection_id)
      end

      # Get a connection by ID
      # @param connection_id [String] connection ID
      # @return [Connection, nil] connection or nil
      def get(connection_id)
        connections[connection_id]
      end

      # Number of active connections
      # @return [Integer] connection count
      def connection_count
        connections.size
      end

      # Reset all connections (for testing)
      def reset!
        @connections = Concurrent::Hash.new
      end

      # Graceful shutdown: close all connections
      # Called on SIGTERM to allow clean dyno restarts
      # Must complete within Heroku's 30s window
      # @param timeout [Integer] max seconds to spend closing connections
      def shutdown(timeout: 25)
        count = connections.size
        return if count.zero?

        Config.logger.info("[NostrRelay] Shutting down #{count} connections...")
        start_time = Time.now
        closed = 0

        # Take a snapshot of connection IDs to avoid iteration issues
        connection_ids = connections.keys

        connection_ids.each_with_index do |conn_id, index|
          # Check timeout
          elapsed = Time.now - start_time
          if elapsed > timeout
            remaining = connection_ids.size - index
            Config.logger.warn("[NostrRelay] Shutdown timeout after #{elapsed.round(1)}s, #{remaining} connections not closed gracefully")
            break
          end

          connection = connections[conn_id]
          next unless connection

          begin
            connection.close(1000, "Server shutting down")
            closed += 1
          rescue StandardError => e
            Config.logger.error("[NostrRelay] Error closing connection #{conn_id}: #{e.message}")
          end
        end

        reset!
        elapsed = (Time.now - start_time).round(2)
        Config.logger.info("[NostrRelay] Shutdown complete: #{closed}/#{count} connections closed in #{elapsed}s")
      end
    end
  end
end
