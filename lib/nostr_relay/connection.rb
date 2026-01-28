# frozen_string_literal: true

require "securerandom"
require "json"

module NostrRelay
  # Handles a single WebSocket connection lifecycle.
  # Protocol-level code lives in lib/nostr_relay/, business logic in app/services/.
  class Connection
    class << self
      def tagged_logger
        @tagged_logger_mutex ||= Mutex.new
        @tagged_logger_mutex.synchronize do
          @tagged_logger ||= AppLogger["NostrRelay::Connection"]
        end
      end
    end

    attr_reader :id

    def initialize(websocket)
      @ws = websocket
      @id = SecureRandom.uuid
      @send_mutex = Mutex.new
    end

    def on_open
      Subscriptions.register(self)
      tagged_logger.info "Connection opened", id: @id
    end

    def on_message(data)
      tagged_logger.debug "Received message", id: @id, preview: data[0..100]

      # Enforce message size limit before processing
      max_length = Config.max_message_length
      if data.bytesize > max_length
        send_notice("#{Messages::Prefix::ERROR} message too large (max #{max_length} bytes)")
        return
      end

      Router.route(connection: self, data:)
    end

    def on_close(code, reason)
      Subscriptions.unregister(@id)
      tagged_logger.info "Connection closed", id: @id, code:, reason:
    end

    def on_error(event)
      message = event.respond_to?(:message) ? event.message : event.to_s
      tagged_logger.error "WebSocket error", id: @id, error: message
      # Connection will be cleaned up by on_close which follows on_error
    end

    # Close the WebSocket connection gracefully
    # Uses mutex to prevent race with concurrent send operations
    def close(code = 1000, reason = "")
      @send_mutex.synchronize do
        @ws.close(code, reason)
      end
    rescue StandardError => e
      tagged_logger.error "Error closing connection", id: @id, error: e.message
    end

    # Outbound message methods per NIP-01
    def send_event(sub_id, event)
      send_message([ Messages::Outbound::EVENT, sub_id, event ])
    end

    def send_ok(event_id, success, message = "")
      send_message([ Messages::Outbound::OK, event_id, success, message ])
    end

    def send_eose(sub_id)
      send_message([ Messages::Outbound::EOSE, sub_id ])
    end

    def send_closed(sub_id, message)
      send_message([ Messages::Outbound::CLOSED, sub_id, message ])
    end

    def send_notice(message)
      send_message([ Messages::Outbound::NOTICE, message ])
    end

    private

    def tagged_logger
      @tagged_logger ||= self.class.tagged_logger
    end

    # Thread-safe message sending
    # faye-websocket buffers writes, mutex prevents concurrent corruption
    def send_message(payload)
      json = payload.to_json
      tagged_logger.debug "Sending message", id: @id, preview: json[0..100]

      @send_mutex.synchronize do
        @ws.send(json)
      end
    rescue StandardError => e
      tagged_logger.error "Failed to send message", id: @id, error: "#{e.class}: #{e.message}"
    end
  end
end
