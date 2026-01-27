# frozen_string_literal: true

# Rack middleware for Nostr WebSocket protocol (NIP-01)
# Intercepts WebSocket connections and delegates to NostrRelay protocol handlers
module NostrRelay
  module Websocket
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        # Debug: Log WebSocket detection
        is_websocket = Faye::WebSocket.websocket?(env)
        Config.logger.debug("[NostrRelay::Middleware] Request: websocket=#{is_websocket}, upgrade=#{env['HTTP_UPGRADE']}, connection=#{env['HTTP_CONNECTION']}")

        if is_websocket
          ws = Faye::WebSocket.new(env, nil, websocket_options)
          connection = NostrRelay::Connection.new(ws)

          ws.on :open do |_event|
            Thread.new do
              Rails.application.executor.wrap do
                connection.on_open
              end
            end
          end

          ws.on :message do |event|
            Thread.new do
              Rails.application.executor.wrap do
                connection.on_message(event.data)
              end
            end
          end

          ws.on :close do |event|
            Thread.new do
              Rails.application.executor.wrap do
                connection.on_close(event.code, event.reason)
              end
            end
          end

          ws.on :error do |event|
            Thread.new do
              Rails.application.executor.wrap do
                connection.on_error(event)
              end
            end
          end

          ws.rack_response
        else
          @app.call(env)
        end
      end

      private

      def websocket_options
        options = {}
        ping_interval = NostrRelay::Config.ping_interval
        options[:ping] = ping_interval if ping_interval&.positive?
        options
      end
    end
  end
end
