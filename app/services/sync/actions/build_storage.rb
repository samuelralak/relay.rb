# frozen_string_literal: true

module Sync
  module Actions
    # Builds a Negentropy storage from a filtered Event scope.
    class BuildStorage < BaseService
      option :filter, type: Types::Hash, default: -> { {} }

      def call
        scope = Event.active

        scope = scope.where(kind: filter[:kinds]) if filter[:kinds].present?
        scope = scope.where("nostr_created_at >= ?", Time.at(filter[:since]).utc) if filter[:since].present?
        scope = scope.where("nostr_created_at <= ?", Time.at(filter[:until]).utc) if filter[:until].present?
        scope = scope.where(pubkey: filter[:authors]) if filter[:authors].present?

        storage = Negentropy::Storage.from_scope(scope)
        Success(storage)
      end
    end
  end
end
