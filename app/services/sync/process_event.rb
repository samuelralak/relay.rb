# frozen_string_literal: true

module Sync
  # Processes and saves an event received from an upstream relay
  class ProcessEvent < BaseService
    option :event_data, type: Types::Hash
    option :source_relay, type: Types::String.optional, default: -> { nil }
    option :broadcast, type: Types::Bool, default: -> { false }

    def call
      return Success(skipped: true, reason: "duplicate") if event_exists?

      event = create_event
      NostrRelay::Subscriptions.broadcast(event) if broadcast
      Success(success: true, event_id: event.event_id)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.message)
    end

    private

    def normalized_data
      @normalized_data ||= Actions::NormalizeEventData.call(event_data:).value!
    end

    def event_exists?
      Event.exists?(event_id:)
    end

    def event_id
      normalized_data[:id]
    end

    def create_event
      Event.create!(
        event_id:,
        pubkey: normalized_data[:pubkey],
        nostr_created_at: Time.at(normalized_data[:created_at]).utc,
        kind: normalized_data[:kind],
        tags: normalized_data[:tags] || [],
        content: normalized_data[:content] || "",
        sig: normalized_data[:sig],
        raw_event: event_data
      )
    end
  end
end
