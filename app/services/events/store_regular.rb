# frozen_string_literal: true

module Events
  class StoreRegular < BaseService
    option :event_data, type: Types::Hash

    def call
      event = Event.new(
        event_id: event_data["id"],
        pubkey: event_data["pubkey"],
        nostr_created_at: Time.at(event_data["created_at"]),
        kind: event_data["kind"],
        tags: event_data["tags"],
        content: event_data["content"],
        sig: event_data["sig"],
        raw_event: event_data.to_json,
        first_seen_at: Time.current
      )

      if event.save
        Success(event)
      else
        Failure[:invalid, "invalid: #{event.errors.full_messages.join(', ')}"]
      end
    rescue ActiveRecord::RecordNotUnique
      # Duplicate event - return success with duplicate marker
      Success(duplicate: true)
    end
  end
end
