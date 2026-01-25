# frozen_string_literal: true

module Events
  module Actions
    class StoreAddressable < BaseService
      option :event_data, type: Types::Hash

      def call
        d_tag_value = extract_d_tag

        # Use transaction with row-level locking to prevent race conditions
        Event.transaction do
          # For addressable events (kinds 30000-39999):
          # Replace any existing event with same pubkey, kind, and "d" tag if newer
          # Use lock to prevent concurrent modifications
          existing = Event.where(
            pubkey: event_data["pubkey"],
            kind: event_data["kind"],
            d_tag: d_tag_value
          ).active
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

          # Soft delete existing event if present (acts_as_paranoid sets deleted_at)
          existing&.destroy

          # Create new event with d_tag column populated
          event = Event.new(
            event_id: event_data["id"],
            pubkey: event_data["pubkey"],
            nostr_created_at: Time.at(event_data["created_at"]),
            kind: event_data["kind"],
            tags: event_data["tags"],
            content: event_data["content"],
            sig: event_data["sig"],
            d_tag: d_tag_value,
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

      private

      def extract_d_tag
        # Find the "d" tag value from tags array
        # Tags format: [["d", "value"], ["other", "tag"]]
        # Handle malformed tags: must be array with at least 2 elements
        d_tag = event_data["tags"]&.find { |tag| tag.is_a?(Array) && tag[0] == "d" && !tag[1].nil? }
        d_tag ? d_tag[1].to_s : ""
      end
    end
  end
end
