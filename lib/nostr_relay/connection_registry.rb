# frozen_string_literal: true

require "concurrent"

module NostrRelay
  # Thread-safe registry for WebSocket connections.
  # Extracted from Subscriptions to separate connection management from subscription logic.
  module ConnectionRegistry
    class << self
      def tagged_logger
        @tagged_logger_mutex ||= Mutex.new
        @tagged_logger_mutex.synchronize do
          @tagged_logger ||= AppLogger["NostrRelay::ConnectionRegistry"]
        end
      end
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

      # Get details for all connections (for stats dashboard)
      # Uses batch subscription count to avoid N+1 lookups
      # Note: connected_at is serialized to ISO8601 for JSON compatibility
      # @return [Array<Hash>] connection details
      def connection_details
        sub_counts = Subscriptions.all_subscription_counts

        connections.map do |id, conn|
          {
            id: id,
            ip_address: conn.ip_address,
            connected_at: conn.connected_at.iso8601,
            authenticated_pubkeys: conn.authenticated_pubkeys.to_a,
            subscription_count: sub_counts[id] || 0
          }
        end
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

        tagged_logger.info("Shutting down connections", count:)
        start_time = Time.now
        closed = 0

        # Take a snapshot of connection IDs to avoid iteration issues
        connection_ids = connections.keys

        connection_ids.each_with_index do |conn_id, index|
          # Check timeout
          elapsed = Time.now - start_time
          if elapsed > timeout
            remaining = connection_ids.size - index
            tagged_logger.warn("Shutdown timeout", elapsed_seconds: elapsed.round(1), remaining:)
            break
          end

          connection = connections[conn_id]
          next unless connection

          begin
            connection.close(1000, "Server shutting down")
            closed += 1
          rescue StandardError => e
            tagged_logger.error "Error closing connection", id: conn_id, error: e.message
          end
        end

        reset!
        elapsed = (Time.now - start_time).round(2)
        tagged_logger.info "Shutdown complete", closed:, total: count, elapsed_seconds: elapsed
      end
    end
  end
end
