# frozen_string_literal: true

require "concurrent"

module NostrRelay
  # Thread-safe subscription manager for WebSocket connections.
  # Lives in lib/ as protocol-level infrastructure.
  module Subscriptions
    class << self
      def connections
        @connections ||= Concurrent::Hash.new
      end

      def subscriptions
        @subscriptions ||= Concurrent::Hash.new { |h, k| h[k] = Concurrent::Hash.new }
      end

      def register(connection)
        connections[connection.id] = connection
      end

      def unregister(connection_id)
        subscriptions.delete(connection_id)
        connections.delete(connection_id)
      end

      # Returns [success, error_message]
      # success: true if subscription was created, false if limit exceeded
      def subscribe(connection_id:, sub_id:, filters:)
        conn_subs = subscriptions[connection_id]

        # Check if this is a new subscription (not replacing existing)
        is_new = !conn_subs.key?(sub_id)

        # Enforce max subscriptions limit from NIP-11
        max_subs = Config.max_subscriptions
        if is_new && conn_subs.size >= max_subs
          return [ false, "#{Messages::Prefix::ERROR} too many subscriptions (max #{max_subs})" ]
        end

        # Cancel existing subscription with same ID (if any)
        conn_subs.delete(sub_id)

        # Store new subscription
        conn_subs[sub_id] = Subscription.new(
          sub_id:,
          filters:
        )

        [ true, nil ]
      end

      def unsubscribe(connection_id, sub_id)
        subscriptions[connection_id].delete(sub_id)
      end

      def broadcast(event)
        event_hash = Config.event_serializer.serialize(event)
        dead_connections = []

        subscriptions.each do |conn_id, subs|
          connection = connections[conn_id]
          next unless connection

          subs.each do |sub_id, subscription|
            next unless subscription.matches?(event)

            unless send_to_connection(connection, sub_id, event_hash)
              dead_connections << conn_id
              break # Skip remaining subscriptions for this dead connection
            end
          end
        end

        # Clean up dead connections after iteration completes
        dead_connections.each { |conn_id| unregister(conn_id) }
      end

      def broadcast_ephemeral(event_data)
        dead_connections = []

        subscriptions.each do |conn_id, subs|
          connection = connections[conn_id]
          next unless connection

          subs.each do |sub_id, subscription|
            next unless subscription.matches_data?(event_data)

            unless send_to_connection(connection, sub_id, event_data)
              dead_connections << conn_id
              break
            end
          end
        end

        dead_connections.each { |conn_id| unregister(conn_id) }
      end

      # For testing: reset all state
      def reset!
        @connections = Concurrent::Hash.new
        @subscriptions = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Hash.new }
      end

      # Graceful shutdown: close all connections
      # Called on SIGTERM to allow clean dyno restarts
      # Must complete within Heroku's 30s window, so we use a timeout
      def shutdown(timeout: 25)
        count = connections.size
        return if count.zero?

        Config.logger.info("[NostrRelay] Shutting down #{count} connections...")
        start_time = Time.now
        closed = 0

        # Take a snapshot of connection IDs to avoid iteration issues
        connection_ids = connections.keys

        connection_ids.each_with_index do |conn_id, index|
          # Check timeout (O(1) instead of O(n) with index lookup)
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

      # Number of active connections (for monitoring)
      def connection_count
        connections.size
      end

      private

      # Returns true on success, false if connection is dead
      def send_to_connection(connection, sub_id, event_data)
        connection.send_event(sub_id, event_data)
        true
      rescue StandardError => e
        Config.logger.error("[NostrRelay] Broadcast error to connection #{connection.id}: #{e.message}")
        false
      end
    end
  end
end
