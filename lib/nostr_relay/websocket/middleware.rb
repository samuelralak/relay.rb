# frozen_string_literal: true

require "concurrent"

# Rack middleware for Nostr WebSocket protocol (NIP-01)
# Intercepts WebSocket connections and delegates to NostrRelay protocol handlers
module NostrRelay
  module Websocket
    class Middleware
      class << self
        def tagged_logger
          @tagged_logger_mutex ||= Mutex.new
          @tagged_logger_mutex.synchronize do
            @tagged_logger ||= AppLogger["NostrRelay::WebSocket::Middleware"]
          end
        end
      end

      # Thread pool to prevent thread exhaustion (Heroku has low ulimit)
      THREAD_POOL = Concurrent::FixedThreadPool.new(
        ENV.fetch("WEBSOCKET_THREAD_POOL_SIZE", 10).to_i,
        max_queue: ENV.fetch("WEBSOCKET_THREAD_POOL_QUEUE", 100).to_i,
        fallback_policy: :discard
      )

      def initialize(app)
        @app = app
      end

      # Paths that should NOT be handled by Nostr WebSocket (e.g., ActionCable)
      EXCLUDED_PATHS = %w[/cable].freeze

      def call(env)
        request_path = env["PATH_INFO"]
        is_websocket = Faye::WebSocket.websocket?(env)
        # Use exact match or path prefix with slash to avoid matching unintended routes
        # e.g., /cable matches but /cableway does not
        is_excluded = EXCLUDED_PATHS.any? do |path|
          request_path == path || request_path.start_with?("#{path}/")
        end

        # Only handle WebSocket connections that are NOT for excluded paths (like ActionCable)
        if is_websocket && !is_excluded
          ws = Faye::WebSocket.new(env, nil, websocket_options)
          connection = NostrRelay::Connection.new(ws, env)

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
          self.class.tagged_logger.error "Thread pool error", error: "#{e.class}: #{e.message}"
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
