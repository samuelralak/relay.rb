# frozen_string_literal: true

require "concurrent"

module NostrRelay
  # Thread-safe subscription manager for WebSocket connections.
  # Lives in lib/ as protocol-level infrastructure.
  #
  # Supports cross-worker broadcasts via Redis pub/sub when REDIS_URL is set.
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

      # Broadcast to local subscribers only (used by both local and remote broadcasts)
      def broadcast_locally(event_hash)
        return if event_expired?(event_hash) # NIP-40

        dead_connections = []

        subscriptions.each do |conn_id, subs|
          connection = connections[conn_id]
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
        data = event_hash.transform_keys(&:to_s)

        subscription.filters.any? do |filter|
          filter = filter.transform_keys(&:to_s)

          # Standard filter checks
          next false if filter["kinds"] && !filter["kinds"].include?(data["kind"])
          next false if filter["authors"] && !filter["authors"].include?(data["pubkey"])
          next false if filter["ids"] && !filter["ids"].include?(data["id"])
          next false if filter["since"] && data["created_at"] < filter["since"]
          next false if filter["until"] && data["created_at"] > filter["until"]

          # Tag filters
          tag_match = filter.all? { |key, values|
            next true unless key.match?(/\A#[a-zA-Z]\z/)
            tag_name = key[1]
            tag_matches_data?(tag_name, Array(values), data["tags"])
          }
          next false unless tag_match

          # NIP-50: Search filter
          search = filter["search"]
          next false if search.present? && !content_matches_search?(data["content"], search)

          true
        end
      end

      # Check if event tags match filter tag values
      def tag_matches_data?(tag_name, filter_values, tags)
        return true if filter_values.empty?
        return false unless tags.is_a?(Array)

        event_vals = tags
          .select { |t| t.is_a?(Array) && t[0] == tag_name && t.size >= 2 }
          .map { |t| t[1] }

        (event_vals & filter_values).any?
      end

      # NIP-50: Simple term matching for search filter
      def content_matches_search?(content, query)
        return true if query.blank?
        terms = query.downcase.split.reject { |t| t.start_with?("-") || t.include?(":") }
        terms.all? { |term| content.to_s.downcase.include?(term) }
      end

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
