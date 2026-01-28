# frozen_string_literal: true

# Diagnostic logging for EventMachine status
# faye-websocket auto-starts EventMachine, but we log status for debugging

if defined?(EventMachine)
  Rails.application.config.after_initialize do
    AppLogger[:EventMachine].info "Loaded", status: defined?(EventMachine)
    AppLogger[:EventMachine].info "Reactor running", status: EventMachine.reactor_running?
  end
end
