# frozen_string_literal: true

require "singleton"
require "logger"

module RelaySync
  # Manages relay connections and coordinates message routing
  # Pure connection management - Rails-specific orchestration handled by service objects
  class Manager
    include Singleton

    attr_reader :connections

    class << self
      attr_writer :logger

      def logger
        @logger ||= Logger.new(File::NULL)
      end
    end

    def initialize
      @connections = {}
      @handlers = HandlerRegistry.new
      @mutex = Mutex.new
    end

    # Set default event handler (delegates to HandlerRegistry)
    def on_event(&handler)
      @handlers.on_event(&handler)
    end

    # Register/unregister handlers (delegates to HandlerRegistry)
    def register_event_handler(subscription_id, &handler)
      @handlers.register_event_handler(subscription_id, &handler)
    end

    def unregister_event_handler(subscription_id)
      @handlers.unregister_event_handler(subscription_id)
    end

    def register_ok_handler(event_id, &handler)
      @handlers.register_ok_handler(event_id, &handler)
    end

    def unregister_ok_handler(event_id)
      @handlers.unregister_ok_handler(event_id)
    end

    def register_neg_handler(subscription_id, reconciler:, error_callback: nil, &callback)
      @handlers.register_neg_handler(subscription_id, reconciler:, error_callback:, &callback)
    end

    def unregister_neg_handler(subscription_id)
      @handlers.unregister_neg_handler(subscription_id)
    end

    def register_eose_handler(subscription_id, &handler)
      @handlers.register_eose_handler(subscription_id, &handler)
    end

    def unregister_eose_handler(subscription_id)
      @handlers.unregister_eose_handler(subscription_id)
    end

    # Add a connection to a relay
    # @param url [String] relay URL
    # @param callbacks [Hash] optional additional callbacks
    # @return [Connection] the created connection
    def add_connection(url, callbacks: {})
      combined_callbacks = build_callbacks.merge(callbacks)
      connection = Connection.new(url:, callbacks: combined_callbacks)

      @mutex.synchronize do
        @connections[url] = connection
      end

      connection.connect
      connection
    end

    # Get a connection to a relay
    # @param url [String] relay URL
    # @return [Connection, nil] relay connection
    def connection_for(url)
      @mutex.synchronize do
        @connections[url]
      end
    end

    # Remove a connection
    # @param url [String] relay URL
    def remove_connection(url)
      @mutex.synchronize do
        connection = @connections.delete(url)
        connection&.disconnect
      end
    end

    # Stop all connections
    def stop
      logger.info "[RelaySync::Manager] Stopping sync manager"

      @mutex.synchronize do
        @connections.values.each(&:disconnect)
        @connections.clear
      end
    end

    # Get status of all connections
    # @return [Hash] status information
    def status
      @mutex.synchronize do
        @connections.transform_values do |conn|
          {
            state: conn.state,
            subscriptions: conn.subscriptions.keys,
            reconnect_attempts: conn.reconnect_attempts
          }
        end
      end
    end

    private

    def logger
      self.class.logger
    end

    def build_callbacks
      {
        on_connect: ->(conn) { handle_connect(conn) },
        on_disconnect: ->(conn, code, reason) { handle_disconnect(conn, code, reason) },
        on_event: ->(conn, sub_id, event) { handle_event(conn, sub_id, event) },
        on_eose: ->(conn, sub_id) { handle_eose(conn, sub_id) },
        on_ok: ->(conn, event_id, success, message) { handle_ok(conn, event_id, success, message) },
        on_error: ->(conn, message) { handle_error(conn, message) },
        on_auth: ->(conn, challenge) { handle_auth(conn, challenge) },
        on_closed: ->(conn, sub_id, message) { handle_closed(conn, sub_id, message) },
        on_neg_msg: ->(conn, sub_id, message) { handle_neg_msg(conn, sub_id, message) },
        on_neg_err: ->(conn, sub_id, error) { handle_neg_err(conn, sub_id, error) }
      }
    end

    # Connection callbacks

    def handle_connect(connection)
      logger.info "[RelaySync::Manager] Connected to #{connection.url}"
    end

    def handle_disconnect(connection, code, reason)
      logger.info "[RelaySync::Manager] Disconnected from #{connection.url}: #{code} - #{reason}"
    end

    def handle_event(connection, subscription_id, event_data)
      # First try subscription-specific handler
      handler = @handlers.event_handler_for(subscription_id)

      if handler
        handler.call(connection, subscription_id, event_data)
      elsif @handlers.default_event_handler
        # Fall back to default handler
        @handlers.default_event_handler.call(connection, subscription_id, event_data)
      end
    end

    def handle_eose(connection, subscription_id)
      logger.debug "[RelaySync::Manager] EOSE for #{subscription_id} from #{connection.url}"

      handler = @handlers.consume_eose_handler(subscription_id)
      handler&.call
    end

    def handle_ok(connection, event_id, success, message)
      logger.debug "[RelaySync::Manager] OK for #{event_id}: #{success} - #{message}"

      handler = @handlers.consume_ok_handler(event_id)
      handler&.call(success, message)
    end

    def handle_error(connection, message)
      logger.error "[RelaySync::Manager] Error from #{connection.url}: #{message}"
    end

    def handle_auth(connection, challenge)
      # NIP-42 authentication challenge received
      # Currently just logs - full implementation requires signing capability
      logger.warn "[RelaySync::Manager] AUTH challenge from #{connection.url} - authentication not implemented"
    end

    def handle_closed(connection, subscription_id, message)
      logger.info "[RelaySync::Manager] CLOSED for #{subscription_id} from #{connection.url}: #{message}"
      # Subscription was closed by the relay - clean up any pending handlers
      unregister_neg_handler(subscription_id)
      unregister_eose_handler(subscription_id)
      unregister_event_handler(subscription_id)
    end

    def handle_neg_msg(connection, subscription_id, message)
      logger.debug "[RelaySync::Manager] NEG-MSG for #{subscription_id} from #{connection.url}"

      handler_info = @handlers.neg_handler_for(subscription_id)
      return unless handler_info

      reconciler = handler_info[:reconciler]
      callback = handler_info[:callback]

      begin
        response_hex, have_ids, need_ids = reconciler.reconcile(message)

        # Notify callback of found IDs
        callback&.call(have_ids, need_ids, response_hex.nil?)

        if response_hex
          # Continue reconciliation
          connection.neg_msg(subscription_id, response_hex)
        else
          # Reconciliation complete
          connection.neg_close(subscription_id)
          @handlers.unregister_neg_handler(subscription_id)
        end
      rescue StandardError => e
        logger.error "[RelaySync::Manager] NEG-MSG processing error: #{e.message}"
        connection.neg_close(subscription_id)
        @handlers.unregister_neg_handler(subscription_id)
      end
    end

    def handle_neg_err(connection, subscription_id, error)
      logger.error "[RelaySync::Manager] NEG-ERR for #{subscription_id} from #{connection.url}: #{error}"

      # Get the error callback before cleaning up
      handler_info = @handlers.neg_handler_for(subscription_id)
      error_callback = handler_info&.dig(:error_callback)

      # Clean up the handler
      @handlers.unregister_neg_handler(subscription_id)

      # Signal the error to waiting code
      error_callback&.call(error)
    end
  end
end
