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

      private

      # Returns true on success, false if connection is dead
      def send_to_connection(connection, sub_id, event_data)
        connection.send_event(sub_id, event_data)
        true
      rescue StandardError => e
        Config.logger.error("[NostrRelay] Broadcast error to connection #{connection.id}: #{e.message}")
        false
      end

      # For testing: reset all state
      def reset!
        @connections = Concurrent::Hash.new
        @subscriptions = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Hash.new }
      end
    end
  end
end
