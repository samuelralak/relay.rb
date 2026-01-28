# frozen_string_literal: true

require "digest"

module Auth
  module Actions
    # Computes the event ID for a Nostr event per NIP-01.
    # The ID is the SHA256 hash of the canonical JSON serialization.
    class ComputeEventId < BaseService
      option :event, type: Types::Hash

      def call
        data = event.transform_keys(&:to_s)

        canonical = [
          0,
          data["pubkey"],
          data["created_at"],
          data["kind"],
          data["tags"],
          data["content"]
        ].to_json

        Success(event_id: Digest::SHA256.hexdigest(canonical))
      end
    end
  end
end
