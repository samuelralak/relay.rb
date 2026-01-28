# frozen_string_literal: true

module NostrRelay
  module Handlers
    # Handles incoming AUTH messages from clients (NIP-42).
    # Validates the signed authentication event and updates connection state.
    module Auth
      include Dry::Monads[:result]

      def self.tagged_logger
        @tagged_logger_mutex ||= Mutex.new
        @tagged_logger_mutex.synchronize do
          @tagged_logger ||= AppLogger["NostrRelay::Handlers::Auth"]
        end
      end

      module_function

      def call(connection:, payload:)
        event_id = extract_event_id(payload)

        # Verify a challenge was issued
        unless connection.challenge
          connection.send_ok(event_id, false, Messages::Prefix.build(Messages::Prefix::ERROR, "no challenge issued"))
          return
        end

        # Validate the AUTH event
        result = ::Auth::ValidateAuthEvent.call(
          event_data: payload,
          connection_challenge: connection.challenge,
          relay_url: Config.relay_url
        )

        case result
        in Success(pubkey:)
          connection.add_authenticated_pubkey(pubkey)
          connection.send_ok(event_id, true, "")
          Auth.tagged_logger.info "Client authenticated", connection_id: connection.id, pubkey: "#{pubkey[0..15]}..."
        in Failure[ :invalid, message ]
          connection.send_ok(event_id, false, message)
          Auth.tagged_logger.warn "AUTH validation failed", connection_id: connection.id, reason: message
        in Failure[ _, message ]
          connection.send_ok(event_id, false, Messages::Prefix.build(Messages::Prefix::ERROR, message))
          Auth.tagged_logger.warn "AUTH error", connection_id: connection.id, reason: message
        end
      rescue StandardError => e
        Auth.tagged_logger.error "Auth handler error", error: "#{e.class}: #{e.message}", backtrace: e.backtrace.first(5)
        connection.send_ok(extract_event_id(payload), false, Messages::Prefix.build(Messages::Prefix::ERROR, "internal error"))
      end

      def extract_event_id(payload)
        return "" unless payload.is_a?(Hash)

        payload["id"]&.to_s || ""
      end
    end
  end
end
