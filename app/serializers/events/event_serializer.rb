# frozen_string_literal: true

module Events
  class EventSerializer < BaseSerializer
    # Serializes an Event to NIP-01 JSON format
    #
    # @example Single event
    #   Events::EventSerializer.serialize(event)
    #   # => { id: "abc...", pubkey: "def...", ... }
    #
    # @example Collection
    #   Events::EventSerializer.serialize(Event.limit(10))
    #   # => [{ id: "abc...", ... }, { id: "def...", ... }]

    def serializable_hash
      {
        id: object.event_id,
        pubkey: object.pubkey,
        created_at: object.nostr_created_at&.to_i,
        kind: object.kind,
        tags: object.tags,
        content: object.content,
        sig: object.sig
      }
    end
  end
end
