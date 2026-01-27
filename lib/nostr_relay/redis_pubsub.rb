# frozen_string_literal: true

require "json"
require "securerandom"

module NostrRelay
  # Redis pub/sub for cross-worker event broadcasts.
  # Enables Puma clustered mode while maintaining broadcast integrity.
  module RedisPubsub
    CHANNEL = "nostr_relay:broadcasts"

    class << self
      # Publish event to Redis for cross-worker broadcast
      # @param type [Symbol] :event or :ephemeral
      # @param data [Hash] serialized event data
      def publish(type:, data:)
        return unless enabled?

        message = { type: type.to_s, data: data, worker_id: worker_id }.to_json
        redis_pool.with { |conn| conn.publish(CHANNEL, message) }
      rescue Redis::BaseError => e
        Config.logger.error("[RedisPubsub] Publish failed: #{e.message}")
      end

      # Start subscriber thread (called on worker boot)
      def start_subscriber
        return unless enabled?
        return if @subscriber_thread&.alive?

        @subscriber_thread = Thread.new { subscribe_loop }
        @subscriber_thread.abort_on_exception = false
        Config.logger.info("[RedisPubsub] Subscriber started: #{worker_id}")
      end

      # Stop subscriber thread (called on shutdown)
      def stop_subscriber
        return unless @subscriber_thread

        @shutdown = true
        @subscriber_redis&.close rescue nil
        @subscriber_thread.join(5) rescue nil
        @subscriber_thread = nil
        Config.logger.info("[RedisPubsub] Subscriber stopped")
      end

      # Check if Redis is configured and available
      def enabled?
        !!redis_url
      end

      # Check if subscriber thread is running
      def subscriber_alive?
        @subscriber_thread&.alive?
      end

      # Unique identifier for this worker process
      def worker_id
        @worker_id ||= "#{Process.pid}-#{SecureRandom.hex(4)}"
      end

      # Reset state (for testing)
      def reset!
        stop_subscriber
        @redis_pool = nil
        @worker_id = nil
        @shutdown = false
      end

      private

      def redis_url
        ENV["REDIS_URL"]
      end

      # Connection pool for publishing (thread-safe)
      def redis_pool
        @redis_pool ||= ConnectionPool.new(size: 5, timeout: 5) do
          Redis.new(url: redis_url)
        end
      end

      def subscribe_loop
        @shutdown = false
        backoff = 1

        loop do
          break if @shutdown

          begin
            @subscriber_redis = Redis.new(url: redis_url)
            backoff = 1 # Reset on success

            @subscriber_redis.subscribe(CHANNEL) do |on|
              on.message { |_, msg| handle_message(msg) }
            end
          rescue Redis::BaseConnectionError => e
            break if @shutdown
            Config.logger.warn("[RedisPubsub] Reconnecting in #{backoff}s: #{e.message}")
            sleep backoff
            backoff = [backoff * 2, 30].min # Exponential backoff, max 30s
          rescue StandardError => e
            break if @shutdown
            Config.logger.error("[RedisPubsub] Error: #{e.class}: #{e.message}")
            sleep backoff
            backoff = [backoff * 2, 30].min
          end
        end
      end

      def handle_message(raw)
        message = JSON.parse(raw, symbolize_names: true)
        return if message[:worker_id] == worker_id # Skip own messages

        case message[:type]
        when "event"
          Subscriptions.broadcast_remote(message[:data])
        when "ephemeral"
          Subscriptions.broadcast_ephemeral_remote(message[:data])
        end
      rescue JSON::ParserError => e
        Config.logger.error("[RedisPubsub] Invalid JSON: #{e.message}")
      rescue StandardError => e
        Config.logger.error("[RedisPubsub] Handle error: #{e.message}")
      end
    end
  end
end
