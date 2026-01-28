# frozen_string_literal: true

require "concurrent"

module NostrRelay
  # Thread-safe subscription manager for WebSocket connections.
  # Lives in lib/ as protocol-level infrastructure.
  #
  # Supports cross-worker broadcasts via Redis pub/sub when REDIS_URL is set.
  # Connection management delegated to ConnectionRegistry.
  module Subscriptions
    class << self
      def tagged_logger
        @tagged_logger_mutex ||= Mutex.new
        @tagged_logger_mutex.synchronize do
          @tagged_logger ||= AppLogger["NostrRelay::Subscriptions"]
        end
      end
      # Delegate connection access to ConnectionRegistry (for backwards compatibility)
      def connections
        ConnectionRegistry.connections
      end

      def subscriptions
        @subscriptions ||= Concurrent::Hash.new { |h, k| h[k] = Concurrent::Hash.new }
      end

      # Register a new connection (delegates to ConnectionRegistry)
      def register(connection)
        ConnectionRegistry.register(connection)
      end

      # Unregister a connection and its subscriptions
      def unregister(connection_id)
        subscriptions.delete(connection_id)
        ConnectionRegistry.unregister(connection_id)
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

      # Broadcast a persisted event to all matching subscriptions
      # Publishes to Redis for cross-worker delivery, then broadcasts locally
      def broadcast(event)
        event_hash = Config.event_serializer.serialize(event)
        RedisPubsub.publish(type: :event, data: event_hash)
        broadcast_locally(event_hash)
      end

      # Called from RedisPubsub when receiving cross-worker message
      # Skips Redis publish to avoid loops
      def broadcast_remote(event_hash)
        broadcast_locally(event_hash)
      end

      # Broadcast an ephemeral event (not persisted) to matching subscriptions
      # Publishes to Redis for cross-worker delivery, then broadcasts locally
      def broadcast_ephemeral(event_data)
        RedisPubsub.publish(type: :ephemeral, data: event_data)
        broadcast_ephemeral_locally(event_data)
      end

      # Called from RedisPubsub when receiving cross-worker ephemeral message
      def broadcast_ephemeral_remote(event_data)
        broadcast_ephemeral_locally(event_data)
      end

      # For testing: reset all state
      def reset!
        @subscriptions = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Hash.new }
        ConnectionRegistry.reset!
      end

      # Graceful shutdown: close all connections (delegates to ConnectionRegistry)
      def shutdown(timeout: 25)
        @subscriptions = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Hash.new }
        ConnectionRegistry.shutdown(timeout:)
      end

      # Number of active connections (delegates to ConnectionRegistry)
      def connection_count
        ConnectionRegistry.connection_count
      end

      private

      # Broadcast to local subscribers only (used by both local and remote broadcasts)
      def broadcast_locally(event_hash)
        return if event_expired?(event_hash) # NIP-40

        dead_connections = []

        subscriptions.each do |conn_id, subs|
          connection = ConnectionRegistry.get(conn_id)
          next unless connection

          subs.each do |sub_id, subscription|
            next unless matches_with_search?(subscription, event_hash)

            unless send_to_connection(connection, sub_id, event_hash)
              dead_connections << conn_id
              break # Skip remaining subscriptions for this dead connection
            end
          end
        end

        dead_connections.each { |conn_id| unregister(conn_id) }
      end

      # Broadcast ephemeral event to local subscribers only
      def broadcast_ephemeral_locally(event_data)
        return if event_expired?(event_data) # NIP-40: Ephemeral events can also expire

        dead_connections = []

        subscriptions.each do |conn_id, subs|
          connection = ConnectionRegistry.get(conn_id)
          next unless connection

          subs.each do |sub_id, subscription|
            next unless matches_with_search?(subscription, event_data)

            unless send_to_connection(connection, sub_id, event_data)
              dead_connections << conn_id
              break
            end
          end
        end

        dead_connections.each { |conn_id| unregister(conn_id) }
      end

      # NIP-40: Check if event is expired by parsing expiration tag
      def event_expired?(data)
        data = data.transform_keys(&:to_s)
        tags = data["tags"] || []
        exp_tag = tags.find { |t| t.is_a?(Array) && t[0] == "expiration" }
        return false unless exp_tag && exp_tag[1]

        Time.at(exp_tag[1].to_i) <= Time.current
      rescue StandardError
        false
      end

      # Match event against subscription filters with NIP-50 search support
      def matches_with_search?(subscription, event_hash)
        FilterMatcher.matches?(subscription.filters, event_hash)
      end

      # Returns true on success, false if connection is dead
      def send_to_connection(connection, sub_id, event_data)
        connection.send_event(sub_id, event_data)
        true
      rescue StandardError => e
        tagged_logger.error "Broadcast error", connection_id: connection.id, error: e.message
        false
      end
    end
  end
end
