# frozen_string_literal: true

module Search
  module Actions
    class BuildQuery < BaseService
      option :parsed_query, type: Types::Hash
      option :filter, type: Types::Hash
      option :limit, type: Types::Integer

      DISPLAY_NAME_BOOST = 2
      PUBKEY_AUTHOR_BOOST = 3

      def call
        Success(query: build_query, size: limit)
      end

      private

      def build_query
        {
          bool: {
            must: must_clauses,
            should: should_clauses,
            must_not: must_not_clauses,
            filter: filter_clauses,
            minimum_should_match:
          }.compact_blank
        }
      end

      def must_clauses
        clauses = []

        # Single efficient match for all terms combined on content
        combined = parsed_query[:terms].join(" ")
        if combined.present?
          clauses << { match: { content: { query: combined, operator: "and" } } }
        end

        # Advanced queries also require exact phrase matches
        unless plain_query?
          parsed_query[:phrases]&.each do |phrase|
            clauses << { match_phrase: { content: phrase } }
          end
        end

        clauses.presence
      end

      def should_clauses
        clauses = []

        # Boost kind:0 profile events with matching display_name
        combined_terms = parsed_query[:terms].join(" ")
        if combined_terms.present?
          clauses << { match: { display_name: { query: combined_terms, boost: DISPLAY_NAME_BOOST } } }
        end

        # Pubkey terms: boost notes by that author + content/tag mentions
        parsed_query[:pubkey_terms]&.each do |hex|
          clauses << { term: { pubkey: { value: hex, boost: PUBKEY_AUTHOR_BOOST } } }
          clauses << { match: { content: { query: hex, boost: 1 } } }
          clauses << { term: { tags: { value: hex, boost: 1 } } }
        end

        clauses.presence
      end

      # When ONLY pubkey_terms exist (no regular terms/phrases), at least one
      # should clause must match. Otherwise should clauses just boost relevance.
      def minimum_should_match
        if parsed_query[:terms].blank? && parsed_query[:phrases].blank? && parsed_query[:pubkey_terms].present?
          1
        end
      end

      def must_not_clauses
        clauses = []

        parsed_query[:exclusions]&.each do |term|
          clauses << { match: { content: term } }
        end

        parsed_query[:excluded_phrases]&.each do |phrase|
          clauses << { match_phrase: { content: phrase } }
        end

        clauses.presence
      end

      def filter_clauses
        clauses = []

        clauses << { terms: { kind: filter[:kinds] } } if filter[:kinds].present?
        clauses << { terms: { pubkey: filter[:authors] } } if filter[:authors].present?
        clauses << { range: { nostr_created_at: { gte: filter[:since] } } } if filter[:since].present?
        clauses << { range: { nostr_created_at: { lte: filter[:until] } } } if filter[:until].present?

        # Tag filters
        filter.each do |key, values|
          next unless key.to_s.match?(/\A#[a-zA-Z]\z/)

          clauses << { terms: { tags: Array(values) } }
        end

        clauses.presence
      end

      def plain_query?
        parsed_query[:query_type] == :plain
      end
    end
  end
end
