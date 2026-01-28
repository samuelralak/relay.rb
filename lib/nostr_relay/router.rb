# frozen_string_literal: true

require "json"

module NostrRelay
  # Routes incoming WebSocket messages to appropriate handlers.
  module Router
    def self.tagged_logger
      @tagged_logger_mutex ||= Mutex.new
      @tagged_logger_mutex.synchronize do
        @tagged_logger ||= AppLogger["NostrRelay::Router"]
      end
    end

    module_function

    def route(connection:, data:)
      message = JSON.parse(data)

      # Validate message is an array with at least one element
      unless message.is_a?(Array) && message.size >= 1
        connection.send_notice("#{Messages::Prefix::ERROR} message must be a JSON array")
        return
      end

      type = message[0]

      case type
      when Messages::Inbound::EVENT
        # EVENT requires: ["EVENT", <event object>]
        unless message.size >= 2 && message[1].is_a?(Hash)
          connection.send_notice("#{Messages::Prefix::ERROR} EVENT message requires an event object")
          return
        end
        Handlers::Event.call(connection:, payload: message[1])

      when Messages::Inbound::REQ
        # REQ requires: ["REQ", <subscription_id>, <filters>...]
        unless message.size >= 2
          connection.send_notice("#{Messages::Prefix::ERROR} REQ message requires a subscription id")
          return
        end
        Handlers::Req.call(connection:, sub_id: message[1], filters: message[2..] || [])

      when Messages::Inbound::CLOSE
        # CLOSE requires: ["CLOSE", <subscription_id>]
        unless message.size >= 2
          connection.send_notice("#{Messages::Prefix::ERROR} CLOSE message requires a subscription id")
          return
        end
        Handlers::Close.call(connection:, sub_id: message[1])

      when Messages::Inbound::AUTH
        # AUTH requires: ["AUTH", <signed event object>] (NIP-42)
        unless message.size >= 2 && message[1].is_a?(Hash)
          connection.send_notice("#{Messages::Prefix::ERROR} AUTH message requires a signed event")
          return
        end
        Handlers::Auth.call(connection:, payload: message[1])

      else
        connection.send_notice("#{Messages::Prefix::ERROR} unknown message type '#{type}'")
      end
    rescue JSON::ParserError
      connection.send_notice("#{Messages::Prefix::INVALID} invalid JSON")
    rescue StandardError => e
      Router.tagged_logger.error "Router error", error: "#{e.class}: #{e.message}", backtrace: e.backtrace.first(5)
      connection.send_notice("#{Messages::Prefix::ERROR} internal error")
    end
  end
end
