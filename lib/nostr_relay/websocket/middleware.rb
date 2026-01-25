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
        if Faye::WebSocket.websocket?(env)
          ws = Faye::WebSocket.new(env)
          connection = NostrRelay::Connection.new(ws)

          ws.on :open do |_event|
            connection.on_open
          end

          ws.on :message do |event|
            connection.on_message(event.data)
          end

          ws.on :close do |event|
            connection.on_close(event.code, event.reason)
          end

          ws.rack_response
        else
          @app.call(env)
        end
      end
    end
  end
end
