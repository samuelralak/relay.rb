# frozen_string_literal: true

require "faye/websocket"
require "json"
require "logger"

module RelaySync
  # WebSocket connection wrapper for connecting to Nostr relays
  # Handles connection lifecycle, reconnection, and message routing
  class Connection
    STATES = %i[disconnected connecting connected closing].freeze

    attr_reader :url, :state, :subscriptions, :reconnect_attempts

    class << self
      attr_writer :logger

      def logger
        @logger ||= RelaySync.logger
      end
    end

    def initialize(url:, callbacks: {})
      @url = url
      @callbacks = callbacks
      @subscriptions = {}
      @state = :disconnected
      @reconnect_attempts = 0
      @mutex = Mutex.new
      @ws = nil
    end

    # Connect to the relay
    def connect
      return if state == :connected || state == :connecting

      @state = :connecting
      start_connection
    end

    # Disconnect from the relay
    def disconnect
      return if state == :disconnected

      @state = :closing
      Reactor.instance.schedule do
        @ws&.close
      end
    end

    # Subscribe to events matching filter
    # @param subscription_id [String] unique subscription ID
    # @param filters [Array<Hash>] Nostr filter objects
    def subscribe(subscription_id, filters)
      @subscriptions[subscription_id] = filters
      send_message([ "REQ", subscription_id, *filters ]) if connected?
    end

    # Unsubscribe from a subscription
    # @param subscription_id [String] subscription ID to close
    def unsubscribe(subscription_id)
      return unless @subscriptions.key?(subscription_id)

      send_message([ "CLOSE", subscription_id ]) if connected?
      @subscriptions.delete(subscription_id)
    end

    # Send an event to the relay
    # @param event [Hash] Nostr event object
    def publish_event(event)
      send_message([ "EVENT", event ])
    end

    # Send Negentropy NEG-OPEN message
    # @param subscription_id [String] subscription ID
    # @param filter [Hash] Nostr filter
    # @param initial_message [String] hex-encoded initial negentropy message
    def neg_open(subscription_id, filter, initial_message)
      send_message([ Negentropy::MessageType::NEG_OPEN, subscription_id, filter, initial_message ])
    end

    # Send Negentropy NEG-MSG message
    # @param subscription_id [String] subscription ID
    # @param message [String] hex-encoded negentropy message
    def neg_msg(subscription_id, message)
      send_message([ Negentropy::MessageType::NEG_MSG, subscription_id, message ])
    end

    # Send Negentropy NEG-CLOSE message
    # @param subscription_id [String] subscription ID
    def neg_close(subscription_id)
      send_message([ Negentropy::MessageType::NEG_CLOSE, subscription_id ])
    end

    def connected?
      state == :connected
    end

    def disconnected?
      state == :disconnected
    end

    private

    def logger
      self.class.logger
    end

    def start_connection
      Reactor.instance.schedule do
        setup_websocket
      end
    end

    def setup_websocket
      @ws = Faye::WebSocket::Client.new(@url)

      @ws.on :open do |_event|
        handle_open
      end

      @ws.on :message do |event|
        handle_message(event.data)
      end

      @ws.on :close do |event|
        handle_close(event)
      end

      @ws.on :error do |event|
        handle_error(event)
      end
    end

    def handle_open
      @state = :connected
      @reconnect_attempts = 0

      logger.info "[RelaySync] Connected to #{url}"
      @callbacks[:on_connect]&.call(self)

      # Resubscribe to all existing subscriptions
      resubscribe_all
    end

    def handle_message(data)
      message = JSON.parse(data)
      route_message(message)
    rescue JSON::ParserError => e
      logger.error "[RelaySync] Invalid JSON from #{url}: #{e.message}"
    end

    def handle_close(event)
      was_connected = state == :connected
      @state = :disconnected

      logger.info "[RelaySync] Disconnected from #{url}: code=#{event.code}"
      @callbacks[:on_disconnect]&.call(self, event.code, event.reason)

      schedule_reconnect if was_connected && @state != :closing
    end

    def handle_error(event)
      logger.error "[RelaySync] Error from #{url}: #{event.message}"
      @callbacks[:on_error]&.call(self, event.message)
    end

    def route_message(message)
      type = message[0]

      case type
      when "EVENT"
        handle_event(message[1], message[2])
      when "EOSE"
        handle_eose(message[1])
      when "OK"
        handle_ok(message[1], message[2], message[3])
      when "NOTICE"
        handle_notice(message[1])
      when "AUTH"
        handle_auth(message[1])
      when "CLOSED"
        handle_closed(message[1], message[2])
      when Negentropy::MessageType::NEG_MSG
        handle_neg_msg(message[1], message[2])
      when Negentropy::MessageType::NEG_ERR
        handle_neg_err(message[1], message[2])
      else
        logger.warn "[RelaySync] Unknown message type from #{url}: #{type}"
      end
    end

    def handle_event(subscription_id, event_data)
      @callbacks[:on_event]&.call(self, subscription_id, event_data)
    end

    def handle_eose(subscription_id)
      @callbacks[:on_eose]&.call(self, subscription_id)
    end

    def handle_ok(event_id, success, message)
      @callbacks[:on_ok]&.call(self, event_id, success, message)
    end

    def handle_notice(message)
      logger.info "[RelaySync] NOTICE from #{url}: #{message}"
      @callbacks[:on_notice]&.call(self, message)
    end

    def handle_auth(challenge)
      logger.info "[RelaySync] AUTH challenge from #{url}"
      @callbacks[:on_auth]&.call(self, challenge)
    end

    def handle_closed(subscription_id, message)
      logger.info "[RelaySync] CLOSED for #{subscription_id} from #{url}: #{message}"
      @subscriptions.delete(subscription_id)
      @callbacks[:on_closed]&.call(self, subscription_id, message)
    end

    def handle_neg_msg(subscription_id, message)
      @callbacks[:on_neg_msg]&.call(self, subscription_id, message)
    end

    def handle_neg_err(subscription_id, error)
      logger.error "[RelaySync] NEG-ERR from #{url}: #{error}"
      @callbacks[:on_neg_err]&.call(self, subscription_id, error)
    end

    def resubscribe_all
      @subscriptions.each do |sub_id, filters|
        send_message([ "REQ", sub_id, *filters ])
      end
    end

    def schedule_reconnect
      @reconnect_attempts += 1
      config = RelaySync.configuration.sync_settings

      return if @reconnect_attempts > config.max_reconnect_attempts

      delay = config.reconnect_delay_seconds * @reconnect_attempts
      logger.info "[RelaySync] Reconnecting to #{url} in #{delay}s (attempt #{@reconnect_attempts})"

      Thread.new do
        sleep delay
        connect if @state == :disconnected
      end
    end

    def send_message(message)
      return unless connected?

      json = message.to_json
      Reactor.instance.schedule do
        @ws&.send(json)
      end
    end
  end
end
