# frozen_string_literal: true

module Sync
  # Processes and saves an event received from an upstream relay
  class ProcessEvent < BaseService
    option :event_data, type: Types::Hash
    option :source_relay, type: Types::String.optional, default: -> { nil }

    def call
      return { skipped: true, reason: "duplicate" } if event_exists?

      event = create_event
      { success: true, event_id: event.event_id }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end

    private

    def event_exists?
      Event.exists?(event_id:)
    end

    def event_id
      event_data[:id] || event_data["id"]
    end

    def create_event
      Event.create!(
        event_id:,
        pubkey: event_data[:pubkey] || event_data["pubkey"],
        nostr_created_at: Time.at(event_data[:created_at] || event_data["created_at"]).utc,
        kind: event_data[:kind] || event_data["kind"],
        tags: event_data[:tags] || event_data["tags"] || [],
        content: event_data[:content] || event_data["content"] || "",
        sig: event_data[:sig] || event_data["sig"],
        raw_event: event_data
      )
    end
  end
end
