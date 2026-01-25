# frozen_string_literal: true

module NostrRelay
  module Handlers
    # Handles incoming EVENT messages from clients.
    module Event
      include Dry::Monads[:result]

      module_function

      def call(connection:, payload:)
        # Extract event_id early for error responses (may be nil if malformed)
        event_id = extract_event_id(payload)

        result = Config.event_processor.call(event_data: payload)

        case result
        in Success(duplicate: true, event_id: id)
          connection.send_ok(id, true, Messages::Prefix::DUPLICATE)
        in Success(event_id: id)
          connection.send_ok(id, true, "")
        in Failure[ :invalid, message ]
          connection.send_ok(event_id, false, message)
        in Failure[ :blocked, message ]
          connection.send_ok(event_id, false, message)
        in Failure[ _, message ]
          connection.send_ok(event_id, false, "#{Messages::Prefix::ERROR} #{message}")
        end
      rescue StandardError => e
        Config.logger.error("[NostrRelay] Event handler error: #{e.class}: #{e.message}")
        connection.send_ok(extract_event_id(payload), false, "#{Messages::Prefix::ERROR} internal error")
      end

      def extract_event_id(payload)
        return "" unless payload.is_a?(Hash)

        payload["id"]&.to_s || ""
      end
    end
  end
end
