# frozen_string_literal: true

# Processes events received from upstream relays
class ProcessEventJob < ApplicationJob
  queue_as :events

  # Discard if event already exists (duplicate)
  discard_on ActiveRecord::RecordNotUnique

  # @param event_json [String] JSON string of the event
  # @param source_relay [String, nil] URL of the relay that sent this event
  def perform(event_json, source_relay = nil)
    event_data = JSON.parse(event_json, symbolize_names: true)

    result = Sync::ProcessEvent.call(
      event_data:,
      source_relay:
    )

    if result.success?
      values = result.value!
      if values[:skipped]
        Rails.logger.info "[ProcessEventJob] Skipped #{event_data[:id][0..7]}... (#{values[:reason]})"
      else
        Rails.logger.info "[ProcessEventJob] Saved event #{values[:event_id][0..7]}... from #{source_relay}"
      end
    else
      Rails.logger.error "[ProcessEventJob] Failed to save event: #{result.failure}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[ProcessEventJob] Invalid JSON: #{e.message}"
  end
end
