# frozen_string_literal: true

module Events
  # NIP-09: Processes deletion request targets.
  # Soft-deletes events referenced by e-tags and a-tags in the deletion event.
  class DeleteEvent < BaseService
    option :deletion_event_id, type: Types::String

    def call
      deletion_event = Event.find_by(id: deletion_event_id)
      return Success(nil) unless deletion_event

      pubkey = deletion_event.pubkey
      deletion_timestamp = deletion_event.nostr_created_at
      tags = deletion_event.tags || []

      # Process "e" tags (event IDs to delete)
      e_tags = tags.select { |t| t.is_a?(Array) && t[0] == "e" && t[1].present? }
      e_tags.each { |tag| delete_by_event_id(tag[1], pubkey) }

      # Process "a" tags (addressable coordinates: "kind:pubkey:d-tag")
      a_tags = tags.select { |t| t.is_a?(Array) && t[0] == "a" && t[1].present? }
      a_tags.each { |tag| delete_by_coordinate(tag[1], pubkey, deletion_timestamp) }

      Success(deletion_event)
    end

    private

    def delete_by_event_id(event_id, pubkey)
      # Only delete if same pubkey AND not a deletion request itself
      Event.where(event_id:, pubkey:)
           .where.not(kind: Kinds::DELETION)
           .find_each(&:destroy)
    end

    def delete_by_coordinate(coordinate, pubkey, deletion_timestamp)
      # Parse coordinate: "kind:pubkey:d-tag"
      parts = coordinate.split(":", 3)
      return unless parts.size == 3

      target_kind = parts[0].to_i
      target_pubkey = parts[1]
      target_d_tag = parts[2]

      # Only delete if deletion pubkey matches coordinate pubkey
      return unless pubkey == target_pubkey

      # Cannot delete deletion requests
      return if target_kind == Kinds::DELETION

      # Delete all versions up to the deletion request's created_at
      Event.where(pubkey: target_pubkey, kind: target_kind, d_tag: target_d_tag)
           .where("nostr_created_at <= ?", deletion_timestamp)
           .find_each(&:destroy)
    end
  end
end
