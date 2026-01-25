# frozen_string_literal: true

module Events
  class StoreReplaceable < BaseService
    option :event_data, type: Types::Hash

    def call
      # Use transaction with row-level locking to prevent race conditions
      Event.transaction do
        # For replaceable events (kinds 0, 3, 10000-19999):
        # Replace any existing event with same pubkey and kind if newer
        # Use lock to prevent concurrent modifications
        existing = Event.where(pubkey: event_data["pubkey"], kind: event_data["kind"])
                        .active
                        .lock("FOR UPDATE SKIP LOCKED")
                        .order(nostr_created_at: :desc)
                        .first

        if existing
          existing_ts = existing.nostr_created_at.to_i
          new_ts = event_data["created_at"]

          # NIP-01: For same timestamp, keep event with lowest id (lexical order)
          if existing_ts > new_ts || (existing_ts == new_ts && existing.event_id <= event_data["id"])
            return Failure[:invalid, "invalid: event is older than existing"]
          end
        end

        # Soft delete existing event if present
        existing&.destroy

        # Create new event
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
      end
    rescue ActiveRecord::RecordNotUnique
      # Duplicate event - return success with duplicate marker
      Success(duplicate: true)
    end
  end
end
