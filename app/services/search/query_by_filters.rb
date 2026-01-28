# frozen_string_literal: true

module Search
  # Query OpenSearch using NIP-01 filter criteria (not full-text search)
  # Falls back to PostgreSQL if OpenSearch unavailable or for tag filters
  # (current index stores tag values without tag names)
  class QueryByFilters < BaseService
    option :filters, type: Types::Array, default: -> { [] }
    option :limit, type: Types::Integer, default: -> { 500 }

    def call
      return Success(events: []) if filters.empty?

      # Fall back to PostgreSQL if:
      # - OpenSearch not enabled (no URL configured)
      # - Filters contain tag queries (index doesn't have tag names)
      if !RelaySearch::Client.enabled? || has_tag_filters?
        return database_fallback
      end

      # Build OpenSearch query from filters
      query = build_opensearch_query

      # Execute search - only fetch event_id field
      response = RelaySearch::Client.client.search(
        index: RelaySearch::IndexConfig::INDEX_NAME,
        body: {
          query:,
          size: limit,
          sort: [ { nostr_created_at: "desc" } ],
          _source: [ "event_id" ]
        }
      )

      # Extract event IDs
      event_ids = response["hits"]["hits"].map { |h| h["_source"]["event_id"] }
      return Success(events: []) if event_ids.empty?

      # Fetch full events from DB by ID (fast primary key lookup)
      # Apply active scope to filter expired/deleted events
      # Preserve OpenSearch ordering
      events_by_id = Event.active.where(event_id: event_ids).index_by(&:event_id)
      ordered_events = event_ids.filter_map { |id| events_by_id[id] }

      Success(events: ordered_events)
    rescue OpenSearch::Transport::Transport::Errors::BadRequest => e
      Rails.logger.error "[Search::QueryByFilters] OpenSearch error: #{e.message}"
      database_fallback
    rescue StandardError => e
      Rails.logger.error "[Search::QueryByFilters] Error: #{e.message}"
      database_fallback
    end

    private

    def has_tag_filters?
      filters.any? do |f|
        f.keys.any? { |k| k.to_s.match?(/\A#[a-zA-Z]\z/) }
      end
    end

    def database_fallback
      events = NostrRelay::Config.event_repository
                 .matching_filters(filters)
                 .limit(limit)
                 .to_a

      Success(events:)
    end

    def build_opensearch_query
      # Each filter is OR'd together (NIP-01 spec)
      should_clauses = filters.map { |f| build_filter_query(f) }

      if should_clauses.size == 1
        should_clauses.first
      else
        { bool: { should: should_clauses, minimum_should_match: 1 } }
      end
    end

    def build_filter_query(filter)
      filter = filter.with_indifferent_access
      must_clauses = []

      # ids filter
      if filter[:ids].present?
        must_clauses << { terms: { event_id: Array(filter[:ids]) } }
      end

      # authors filter
      if filter[:authors].present?
        must_clauses << { terms: { pubkey: Array(filter[:authors]) } }
      end

      # kinds filter
      if filter[:kinds].present?
        must_clauses << { terms: { kind: Array(filter[:kinds]) } }
      end

      # since filter (created_at >= since)
      if filter[:since].present?
        must_clauses << { range: { nostr_created_at: { gte: filter[:since] } } }
      end

      # until filter (created_at <= until)
      if filter[:until].present?
        must_clauses << { range: { nostr_created_at: { lte: filter[:until] } } }
      end

      if must_clauses.empty?
        { match_all: {} }
      else
        { bool: { must: must_clauses } }
      end
    end
  end
end
