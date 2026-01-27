# frozen_string_literal: true

require "securerandom"
require "json"

module NostrRelay
  # Handles a single WebSocket connection lifecycle.
  # Protocol-level code lives in lib/nostr_relay/, business logic in app/services/.
  class Connection
    attr_reader :id

    def initialize(websocket)
      @ws = websocket
      @id = SecureRandom.uuid
      @send_mutex = Mutex.new
    end

    def on_open
      Subscriptions.register(self)
      Config.logger.info("[NostrRelay] Connection opened: #{@id}")
    end

    def on_message(data)
      Config.logger.debug("[NostrRelay] Received from #{@id}: #{data[0..100]}...")

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
      Config.logger.info("[NostrRelay] Connection closed: #{@id} (code=#{code}, reason=#{reason})")
    end

    def on_error(event)
      message = event.respond_to?(:message) ? event.message : event.to_s
      Config.logger.error("[NostrRelay] WebSocket error on #{@id}: #{message}")
      # Connection will be cleaned up by on_close which follows on_error
    end

    # Close the WebSocket connection gracefully
    # Uses mutex to prevent race with concurrent send operations
    def close(code = 1000, reason = "")
      @send_mutex.synchronize do
        @ws.close(code, reason)
      end
    rescue StandardError => e
      Config.logger.error("[NostrRelay] Error closing connection #{@id}: #{e.message}")
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

    # Thread-safe message sending
    # faye-websocket buffers writes, mutex prevents concurrent corruption
    def send_message(payload)
      json = payload.to_json
      Config.logger.debug("[NostrRelay] Sending to #{@id}: #{json[0..100]}...")

      @send_mutex.synchronize do
        @ws.send(json)
      end
    rescue StandardError => e
      Config.logger.error("[NostrRelay] Failed to send message to #{@id}: #{e.class}: #{e.message}")
    end
  end
end
