# frozen_string_literal: true

module NostrRelay
  # Worker lifecycle helpers for Puma clustered mode.
  # Consolidates boot/shutdown logic for cleaner puma.rb.
  module Lifecycle
    module_function

    # Called on Puma worker boot (clustered mode)
    def on_worker_boot
      RedisPubsub.reset!
      RedisPubsub.start_subscriber
      start_eventmachine_reactor
    end

    # Called on Puma worker shutdown and at_exit
    def on_shutdown
      RedisPubsub.stop_subscriber
      Subscriptions.shutdown if Subscriptions.connection_count > 0
      stop_eventmachine_reactor
    end

    # Start EventMachine reactor in a background thread
    def start_eventmachine_reactor
      return if !defined?(EventMachine) || EventMachine.reactor_running?

      Thread.new do EventMachine.run end
      sleep 0.1 # Allow reactor to start
      Rails.logger.info("[NostrRelay] EventMachine reactor started: #{EventMachine.reactor_running?}")
    end

    # Stop EventMachine reactor if running
    def stop_eventmachine_reactor
      EventMachine.stop if defined?(EventMachine) && EventMachine.reactor_running?
    end
  end
end
