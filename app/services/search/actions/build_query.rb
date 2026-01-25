# frozen_string_literal: true

module Search
  module Actions
    class BuildQuery < BaseService
      option :parsed_query, type: Types::Hash
      option :filter, type: Types::Hash
      option :limit, type: Types::Integer

      def call
        Success(query: build_query, size: limit)
      end

      private

      def build_query
        {
          bool: {
            must: must_clauses,
            must_not: must_not_clauses,
            filter: filter_clauses
          }.compact_blank
        }
      end

      def must_clauses
        clauses = []

        # Terms (AND logic - all must match)
        parsed_query[:terms]&.each do |term|
          clauses << { match: { content: { query: term, operator: "and" } } }
        end

        # Phrases (exact sequence)
        parsed_query[:phrases]&.each do |phrase|
          clauses << { match_phrase: { content: phrase } }
        end

        clauses.presence
      end

      def must_not_clauses
        clauses = []

        # Excluded terms
        parsed_query[:exclusions]&.each do |term|
          clauses << { match: { content: term } }
        end

        # Excluded phrases (e.g., -"exact phrase")
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
    end
  end
end
