# frozen_string_literal: true

module Search
  module Actions
    # Resolves a username to pubkeys by searching kind:0 profile events.
    # Used when a search query looks like a username (identity_hint).
    # Returns up to MAX_RESOLVED_PROFILES pubkeys for author boosting.
    class ResolveIdentity < BaseService
      include Loggable

      MAX_RESOLVED_PROFILES = 5

      option :username, type: Types::String

      def call
        return Failure(:search_disabled) unless RelaySearch::Client.available?
        return Failure(:empty_username) if username.blank?

        response = RelaySearch::Client.client.search(
          index: RelaySearch::IndexConfig::INDEX_NAME,
          body: {
            query: {
              bool: {
                filter: [
                  { term: { kind: Events::Kinds::METADATA } }
                ],
                must: [
                  { match: { display_name: { query: username, operator: "and" } } }
                ]
              }
            },
            size: MAX_RESOLVED_PROFILES,
            _source: [ "pubkey" ]
          }
        )

        pubkeys = response["hits"]["hits"].map { |h| h["_source"]["pubkey"] }.uniq
        Success(pubkeys:)
      rescue StandardError => e
        logger.warn "Identity resolution failed", error: e.message
        Success(pubkeys: [])
      end
    end
  end
end
