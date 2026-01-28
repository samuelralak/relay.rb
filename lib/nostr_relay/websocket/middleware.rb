# frozen_string_literal: true

require "concurrent"

# Rack middleware for Nostr WebSocket protocol (NIP-01)
# Intercepts WebSocket connections and delegates to NostrRelay protocol handlers
module NostrRelay
  module Websocket
    class Middleware
      # Thread pool to prevent thread exhaustion (Heroku has low ulimit)
      THREAD_POOL = Concurrent::FixedThreadPool.new(
        ENV.fetch("WEBSOCKET_THREAD_POOL_SIZE", 10).to_i,
        max_queue: ENV.fetch("WEBSOCKET_THREAD_POOL_QUEUE", 100).to_i,
        fallback_policy: :discard
      )

      def initialize(app)
        @app = app
      end

      def call(env)
        is_websocket = Faye::WebSocket.websocket?(env)

        if is_websocket
          ws = Faye::WebSocket.new(env, nil, websocket_options)
          connection = NostrRelay::Connection.new(ws)

          ws.on :open do |_event|
            execute_async { connection.on_open }
          end

          ws.on :message do |event|
            execute_async { connection.on_message(event.data) }
          end

          ws.on :close do |event|
            execute_async { connection.on_close(event.code, event.reason) }
          end

          ws.on :error do |event|
            execute_async { connection.on_error(event) }
          end

          ws.rack_response
        else
          @app.call(env)
        end
      end

      private

      def execute_async(&)
        THREAD_POOL.post do
          Rails.application.executor.wrap(&)
        rescue StandardError => e
          Config.logger.error("[NostrRelay] Thread pool error: #{e.class}: #{e.message}")
        end
      end

      def websocket_options
        options = {}
        ping_interval = NostrRelay::Config.ping_interval
        options[:ping] = ping_interval if ping_interval&.positive?
        options
      end
    end
  end
end
