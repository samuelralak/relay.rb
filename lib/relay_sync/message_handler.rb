# frozen_string_literal: true

require "json"

module RelaySync
  # Handles parsing and validation of Nostr relay messages
  module MessageHandler
    module_function

    # Parse a raw JSON message into a structured format
    # @param raw [String] raw JSON string
    # @return [Hash] parsed message with :type and relevant fields
    def parse(raw)
      message = JSON.parse(raw)
      type = message[0]

      case type
      when "EVENT"
        parse_event(message)
      when "EOSE"
        parse_eose(message)
      when "OK"
        parse_ok(message)
      when "NOTICE"
        parse_notice(message)
      when "NEG-MSG"
        parse_neg_msg(message)
      when "NEG-ERR"
        parse_neg_err(message)
      when "CLOSED"
        parse_closed(message)
      when "AUTH"
        parse_auth(message)
      else
        { type: :unknown, raw: message }
      end
    rescue JSON::ParserError => e
      { type: :error, message: "Invalid JSON: #{e.message}" }
    end

    # Build a REQ message for subscribing to events
    # @param subscription_id [String] unique subscription ID
    # @param filters [Array<Hash>] Nostr filter objects
    # @return [Array] REQ message array
    def build_req(subscription_id, *filters)
      [ "REQ", subscription_id, *filters ]
    end

    # Build a CLOSE message for unsubscribing
    # @param subscription_id [String] subscription ID
    # @return [Array] CLOSE message array
    def build_close(subscription_id)
      [ "CLOSE", subscription_id ]
    end

    # Build an EVENT message for publishing
    # @param event [Hash] Nostr event object
    # @return [Array] EVENT message array
    def build_event(event)
      [ "EVENT", event ]
    end

    # Build a NEG-OPEN message for Negentropy sync
    # @param subscription_id [String] subscription ID
    # @param filter [Hash] Nostr filter
    # @param initial_message [String] hex-encoded initial message
    # @return [Array] NEG-OPEN message array
    def build_neg_open(subscription_id, filter, initial_message)
      [ "NEG-OPEN", subscription_id, filter, initial_message ]
    end

    # Build a NEG-MSG message for Negentropy sync
    # @param subscription_id [String] subscription ID
    # @param message [String] hex-encoded message
    # @return [Array] NEG-MSG message array
    def build_neg_msg(subscription_id, message)
      [ "NEG-MSG", subscription_id, message ]
    end

    # Build a NEG-CLOSE message
    # @param subscription_id [String] subscription ID
    # @return [Array] NEG-CLOSE message array
    def build_neg_close(subscription_id)
      [ "NEG-CLOSE", subscription_id ]
    end

    # Validate a Nostr event structure
    # @param event [Hash] event to validate
    # @return [Boolean] true if valid
    def valid_event?(event)
      return false unless event.is_a?(Hash)

      required_keys = %w[id pubkey created_at kind tags content sig]
      required_keys.all? { |k| event.key?(k) || event.key?(k.to_sym) }
    end

    private_class_method def self.parse_event(message)
      {
        type: :event,
        subscription_id: message[1],
        event: message[2]
      }
    end

    private_class_method def self.parse_eose(message)
      {
        type: :eose,
        subscription_id: message[1]
      }
    end

    private_class_method def self.parse_ok(message)
      {
        type: :ok,
        event_id: message[1],
        success: message[2],
        message: message[3]
      }
    end

    private_class_method def self.parse_notice(message)
      {
        type: :notice,
        message: message[1]
      }
    end

    private_class_method def self.parse_neg_msg(message)
      {
        type: :neg_msg,
        subscription_id: message[1],
        message: message[2]
      }
    end

    private_class_method def self.parse_neg_err(message)
      {
        type: :neg_err,
        subscription_id: message[1],
        error: message[2]
      }
    end

    private_class_method def self.parse_closed(message)
      {
        type: :closed,
        subscription_id: message[1],
        message: message[2]
      }
    end

    private_class_method def self.parse_auth(message)
      {
        type: :auth,
        challenge: message[1]
      }
    end
  end
end
