# frozen_string_literal: true

module Events
  # Processes events received from upstream relays
  class ProcessJob < ApplicationJob
    include JobLoggable

    queue_as :events

    # Discard if event already exists (duplicate)
    discard_on ActiveRecord::RecordNotUnique

    # @param event_json [String] JSON string of the event
    # @param source_relay [String, nil] URL of the relay that sent this event
    # @param broadcast [Boolean] Whether to broadcast to subscribers (default: false)
    def perform(event_json, source_relay = nil, broadcast: false)
      event_data = JSON.parse(event_json, symbolize_names: true)

      result = ::Sync::ProcessEvent.call(
        event_data:,
        source_relay:,
        broadcast:
      )

      if result.success?
        values = result.value!
        if values[:skipped]
          logger.info "Skipped event", event_id: event_data[:id][0..7], reason: values[:reason]
        else
          logger.info "Saved event", event_id: values[:event_id][0..7], source_relay:
        end
      else
        logger.error "Failed to save event", failure: result.failure
      end
    rescue JSON::ParserError => e
      logger.error "Invalid JSON", error: e.message
    end
  end
end
