# frozen_string_literal: true

module RelaySync
  # Thread-safe registry for message handlers.
  # Extracted from Manager to separate handler registration from connection management.
  class HandlerRegistry
    def initialize
      @ok_handlers = {}     # event_id => callback
      @neg_handlers = {}    # subscription_id => { reconciler:, callback:, error_callback: }
      @eose_handlers = {}   # subscription_id => callback
      @event_handlers = {}  # subscription_id => callback
      @default_event_handler = nil # fallback for unmatched events
      @mutex = Mutex.new
    end

    # Set default event handler for events without a registered subscription handler
    # @param handler [Proc] callback receiving (connection, subscription_id, event_data)
    def on_event(&handler)
      @default_event_handler = handler
    end

    # Get the default event handler
    # @return [Proc, nil] default handler or nil
    def default_event_handler
      @default_event_handler
    end

    # Register an event handler for a specific subscription
    # @param subscription_id [String] subscription ID to handle
    # @param handler [Proc] callback receiving (connection, subscription_id, event_data)
    def register_event_handler(subscription_id, &handler)
      @mutex.synchronize do
        if @event_handlers[subscription_id]
          RelaySync.logger.warn "[RelaySync::HandlerRegistry] Overwriting existing event handler for #{subscription_id}"
        end
        @event_handlers[subscription_id] = handler
      end
    end

    # Unregister event handler for a subscription
    def unregister_event_handler(subscription_id)
      @mutex.synchronize do
        @event_handlers.delete(subscription_id)
      end
    end

    # Get event handler for a subscription
    # @return [Proc, nil] handler or nil
    def event_handler_for(subscription_id)
      @mutex.synchronize { @event_handlers[subscription_id] }
    end

    # Register a handler for OK response
    # @param event_id [String] event ID to wait for
    # @param handler [Proc] callback receiving (success, message)
    def register_ok_handler(event_id, &handler)
      @mutex.synchronize do
        @ok_handlers[event_id] = handler
      end
    end

    # Unregister OK handler
    def unregister_ok_handler(event_id)
      @mutex.synchronize do
        @ok_handlers.delete(event_id)
      end
    end

    # Consume and return OK handler (removes from registry)
    # @return [Proc, nil] handler or nil
    def consume_ok_handler(event_id)
      @mutex.synchronize { @ok_handlers.delete(event_id) }
    end

    # Register a Negentropy session handler
    # @param subscription_id [String] NEG subscription ID
    # @param reconciler [Negentropy::Reconciler::Client] reconciler instance
    # @param error_callback [Proc] optional callback receiving (error_message) on NEG-ERR
    # @param callback [Proc] callback receiving (have_ids, need_ids, complete)
    def register_neg_handler(subscription_id, reconciler:, error_callback: nil, &callback)
      @mutex.synchronize do
        @neg_handlers[subscription_id] = {
          reconciler:,
          callback:,
          error_callback:
        }
      end
    end

    # Unregister Negentropy handler
    def unregister_neg_handler(subscription_id)
      @mutex.synchronize do
        @neg_handlers.delete(subscription_id)
      end
    end

    # Get Negentropy handler info for a subscription
    # @return [Hash, nil] handler info or nil
    def neg_handler_for(subscription_id)
      @mutex.synchronize { @neg_handlers[subscription_id] }
    end

    # Register a handler for EOSE response
    # @param subscription_id [String] subscription ID to wait for
    # @param handler [Proc] callback called when EOSE received
    def register_eose_handler(subscription_id, &handler)
      @mutex.synchronize do
        if @eose_handlers[subscription_id]
          RelaySync.logger.warn "[RelaySync::HandlerRegistry] Overwriting existing EOSE handler for #{subscription_id}"
        end
        @eose_handlers[subscription_id] = handler
      end
    end

    # Unregister EOSE handler
    def unregister_eose_handler(subscription_id)
      @mutex.synchronize do
        @eose_handlers.delete(subscription_id)
      end
    end

    # Consume and return EOSE handler (removes from registry)
    # @return [Proc, nil] handler or nil
    def consume_eose_handler(subscription_id)
      @mutex.synchronize { @eose_handlers.delete(subscription_id) }
    end
  end
end
