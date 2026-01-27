# frozen_string_literal: true

# Diagnostic logging for EventMachine status
# faye-websocket auto-starts EventMachine, but we log status for debugging

if defined?(EventMachine)
  Rails.application.config.after_initialize do
    Rails.logger.info("[EventMachine] Loaded: #{defined?(EventMachine)}")
    Rails.logger.info("[EventMachine] Reactor running: #{EventMachine.reactor_running?}")
  end
end
