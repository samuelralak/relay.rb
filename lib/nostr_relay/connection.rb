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

    attr_reader :id, :challenge, :authenticated_pubkeys, :ip_address, :connected_at

    def initialize(websocket, env = {})
      @ws = websocket
      @id = SecureRandom.uuid
      @send_mutex = Mutex.new
      @challenge = nil
      @authenticated_pubkeys = Set.new
      @ip_address = extract_ip_address(env)
      @connected_at = Time.current
    end

    def on_open
      Subscriptions.register(self)
      send_auth_challenge if Config.auth_enabled?
      tagged_logger.info "Connection opened", id: @id
    end

    # NIP-42: Check if connection is authenticated
    # @param pubkey [String, nil] Optional pubkey to check. If nil, checks if any pubkey is authenticated.
    # @return [Boolean] True if authenticated
    def authenticated?(pubkey = nil)
      if pubkey
        @authenticated_pubkeys.include?(pubkey)
      else
        @authenticated_pubkeys.any?
      end
    end

    # NIP-42: Add an authenticated pubkey to this connection
    # @param pubkey [String] The authenticated pubkey (64 hex chars)
    def add_authenticated_pubkey(pubkey)
      @authenticated_pubkeys.add(pubkey)
      tagged_logger.info "Pubkey authenticated", id: @id, pubkey: "#{pubkey[0..15]}..."
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

    # NIP-42: Send AUTH challenge to client
    # @param challenge [String] The challenge string
    def send_auth(challenge)
      send_message([ Messages::Outbound::AUTH, challenge ])
    end

    private

    # NIP-42: Generate and send authentication challenge on connection open
    def send_auth_challenge
      result = ::Auth::Actions::GenerateChallenge.call
      if result.success?
        @challenge = result.value![:challenge]
        send_auth(@challenge)
        tagged_logger.debug "AUTH challenge sent", id: @id
      end
    end

    # Extract client IP address from Rack env
    # @param env [Hash] Rack environment
    # @return [String, nil] IP address or nil if not found
    def extract_ip_address(env)
      return nil if env.empty?

      env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
        env["HTTP_X_REAL_IP"] ||
        env["REMOTE_ADDR"]
    end

    def tagged_logger
      @tagged_logger ||= self.class.tagged_logger
    end

    # Thread-safe message sending
    # Schedule on EM reactor to ensure immediate delivery when called from thread pool
    def send_message(payload)
      json = payload.to_json
      tagged_logger.debug "Sending message", id: @id, preview: json[0..100]

      if EM.reactor_running?
        # Schedule on reactor thread for immediate processing
        EM.next_tick do
          @send_mutex.synchronize { @ws.send(json) }
        end
      else
        @send_mutex.synchronize { @ws.send(json) }
      end
    rescue StandardError => e
      tagged_logger.error "Failed to send message", id: @id, error: "#{e.class}: #{e.message}"
    end
  end
end
