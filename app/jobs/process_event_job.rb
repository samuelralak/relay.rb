# frozen_string_literal: true

# Processes events received from upstream relays
class ProcessEventJob < ApplicationJob
  queue_as :default

  # Discard if event already exists (duplicate)
  discard_on ActiveRecord::RecordNotUnique

  # @param event_json [String] JSON string of the event
  # @param source_relay [String, nil] URL of the relay that sent this event
  def perform(event_json, source_relay = nil)
    event_data = JSON.parse(event_json, symbolize_names: true)

    # Skip if event already exists
    return if Event.exists?(event_id: event_data[:id])

    # Create the event
    Event.create!(
      event_id: event_data[:id],
      pubkey: event_data[:pubkey],
      nostr_created_at: Time.at(event_data[:created_at]).utc,
      kind: event_data[:kind],
      tags: event_data[:tags] || [],
      content: event_data[:content] || "",
      sig: event_data[:sig],
      raw_event: event_data
    )

    Rails.logger.debug "[ProcessEventJob] Saved event #{event_data[:id][0..7]}... from #{source_relay}"
  rescue JSON::ParserError => e
    Rails.logger.error "[ProcessEventJob] Invalid JSON: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[ProcessEventJob] Validation failed for event #{event_data&.dig(:id)}: #{e.message}"
  end
end
