# frozen_string_literal: true

module Search
  class ExecuteSearch < BaseService
    include Loggable

    option :search_query, type: Types::String
    option :filter, type: Types::Hash, default: -> { {} }
    option :limit, type: Types::Integer, default: -> { 500 }

    def call
      return Failure(:search_disabled) unless RelaySearch::Client.available?
      return Failure(:empty_query) if search_query.blank?

      # 1. Parse query
      parsed = Actions::ParseQuery.call(query: search_query).value!

      # 2. Require at least one positive search signal
      # (term, phrase, OR pubkey term)
      has_positive = parsed[:terms].any? || parsed[:phrases].any? || parsed[:pubkey_terms].any?
      return Failure(:empty_query) unless has_positive

      # 3. Resolve identity if hinted (username → pubkeys)
      parsed = resolve_identity_if_needed(parsed)

      # 4. Check for include:spam extension
      include_spam = parsed[:extensions]["include"] == "spam"

      # 5. Merge from: extension authors with filter authors
      effective_filter = merge_from_authors(filter, parsed[:from_authors])

      # 6. Enforce search_max_limit
      effective_limit = [ limit, NostrRelay::Config.search_max_limit ].min

      # 7. Build OpenSearch query
      query_result = Actions::BuildQuery.call(
        parsed_query: parsed,
        filter: effective_filter,
        limit: effective_limit
      )

      # 8. Execute search with relevance + recency sorting
      response = RelaySearch::Client.client.search(
        index: RelaySearch::IndexConfig::INDEX_NAME,
        body: {
          query: query_result.value![:query],
          size: query_result.value![:size],
          sort: [
            { _score: "desc" },
            { nostr_created_at: "desc" }
          ],
          _source: [ "event_id" ]
        }
      )

      # 9. Extract event IDs preserving relevance order
      event_ids = response["hits"]["hits"].map { |h| h["_source"]["event_id"] }
      return Success(events: [], total: 0) if event_ids.empty?

      # 10. Fetch events from DB, preserving OpenSearch relevance order
      events_by_id = Event.active.where(event_id: event_ids).index_by(&:event_id)
      ordered_events = event_ids.filter_map { |id| events_by_id[id] }

      # 11. Apply spam filtering unless include:spam
      ordered_events = filter_spam(ordered_events) unless include_spam

      Success(events: ordered_events, total: response["hits"]["total"]["value"])
    rescue StandardError => e
      logger.error "Search error", error: e.message
      Failure(:search_error)
    end

    private

    # When the query looks like a username search (identity_hint)
    # and no pubkeys were already extracted, try resolving the term
    # as a username via kind:0 profile display_name matches.
    def resolve_identity_if_needed(parsed)
      return parsed unless parsed[:identity_hint]
      return parsed if parsed[:pubkey_terms].any?
      return parsed if parsed[:terms].empty?

      username = parsed[:terms].first
      result = Actions::ResolveIdentity.call(username:)

      if result.success? && result.value![:pubkeys].any?
        parsed.merge(pubkey_terms: result.value![:pubkeys])
      else
        parsed
      end
    end

    # Merge from: extension authors with existing filter authors.
    # If both exist, uses intersection (AND logic).
    # If only one exists, uses that list.
    def merge_from_authors(base_filter, from_authors)
      return base_filter if from_authors.blank?

      existing_authors = Array(base_filter[:authors]).presence

      merged_authors = if existing_authors
                         # Intersection: both filter and from: must match
                         existing_authors & from_authors
      else
                         from_authors
      end

      base_filter.merge(authors: merged_authors)
    end

    def filter_spam(events)
      # NIP-50 SHOULD: Exclude spam from search results by default
      # Heuristics:
      # - Very short content (< 3 chars)
      # - Excessive character repetition (10+ same char in a row)
      # - Excessive whitespace ratio (> 50% whitespace)
      events.reject do |event|
        content = event.content.to_s
        next true if content.length < 3
        next true if content.match?(/(.)\1{10,}/)
        next true if content.length > 10 && content.count(" \t\n\r").to_f / content.length > 0.5

        false
      end
    end
  end
end
