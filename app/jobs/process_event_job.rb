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
      event_data: event_data,
      source_relay: source_relay
    )

    if result[:success]
      Rails.logger.info "[ProcessEventJob] Saved event #{result[:event_id][0..7]}... from #{source_relay}"
    elsif result[:skipped]
      Rails.logger.info "[ProcessEventJob] Skipped #{event_data[:id][0..7]}... (#{result[:reason]})"
    else
      Rails.logger.error "[ProcessEventJob] Failed to save event: #{result[:error]}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[ProcessEventJob] Invalid JSON: #{e.message}"
  end
end
