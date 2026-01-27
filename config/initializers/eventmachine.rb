# frozen_string_literal: true

# Ensure EventMachine reactor is running for faye-websocket
# Required for WebSocket support with Puma on Heroku
#
# faye-websocket depends on EventMachine for async I/O.
# Puma is multi-threaded, but EventMachine needs its reactor running.
# This initializer ensures the reactor starts before any WebSocket connections.

if defined?(EventMachine) && defined?(Faye::WebSocket)
  Rails.application.config.after_initialize do
    # Only start if not already running
    unless EventMachine.reactor_running?
      Thread.new do
        EventMachine.run
      end

      # Wait for reactor to start (max 5 seconds)
      50.times do
        break if EventMachine.reactor_running?
        sleep 0.1
      end

      if EventMachine.reactor_running?
        Rails.logger.info("[EventMachine] Reactor started successfully")
      else
        Rails.logger.error("[EventMachine] Failed to start reactor!")
      end
    end
  end
end
