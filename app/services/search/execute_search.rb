# frozen_string_literal: true

module Search
  class ExecuteSearch < BaseService
    include Loggable

    option :search_query, type: Types::String
    option :filter, type: Types::Hash, default: -> { {} }
    option :limit, type: Types::Integer, default: -> { 100 }

    def call
      return Failure(:search_disabled) unless RelaySearch::Client.available?
      return Failure(:empty_query) if search_query.blank?

      # 1. Parse query
      parsed = Actions::ParseQuery.call(query: search_query).value!

      # 2. Require at least one positive search term (term or phrase)
      # Prevents overly broad queries with only exclusions or extensions
      return Failure(:empty_query) if parsed[:terms].empty? && parsed[:phrases].empty?

      # 3. Check for include:spam extension
      include_spam = parsed[:extensions]["include"] == "spam"

      # 4. Merge from: extension authors with filter authors
      effective_filter = merge_from_authors(filter, parsed[:from_authors])

      # 5. Enforce search_max_limit
      effective_limit = [ limit, NostrRelay::Config.search_max_limit ].min

      # 6. Build OpenSearch query
      query_result = Actions::BuildQuery.call(
        parsed_query: parsed,
        filter: effective_filter,
        limit: effective_limit
      )

      # 7. Execute search
      response = RelaySearch::Client.client.search(
        index: RelaySearch::IndexConfig::INDEX_NAME,
        body: {
          query: query_result.value![:query],
          size: query_result.value![:size],
          sort: [ { _score: "desc" } ]  # Relevance ordering (NIP-50 requirement)
        }
      )

      # 8. Extract event IDs preserving relevance order
      event_ids = response["hits"]["hits"].map { |h| h["_source"]["event_id"] }
      return Success(events: [], total: 0) if event_ids.empty?

      # 9. Fetch events from DB, preserving OpenSearch relevance order
      events_by_id = Event.where(event_id: event_ids).index_by(&:event_id)
      ordered_events = event_ids.filter_map { |id| events_by_id[id] }

      # 10. Apply spam filtering unless include:spam
      ordered_events = filter_spam(ordered_events) unless include_spam

      Success(events: ordered_events, total: response["hits"]["total"]["value"])
    rescue StandardError => e
      logger.error "Search error", error: e.message
      Failure(:search_error)
    end

    private

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
