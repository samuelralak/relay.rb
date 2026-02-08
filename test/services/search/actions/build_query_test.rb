# frozen_string_literal: true

require "test_helper"

module Search
  module Actions
    class BuildQueryTest < ActiveSupport::TestCase
      # =========================================================================
      # Plain Text Queries (Strategy A)
      # =========================================================================

      test "plain query uses single match on content" do
        parsed = plain_parsed(terms: %w[bitcoin lightning])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        must = query[:bool][:must]

        assert_equal 1, must.size
        assert_equal "bitcoin lightning", must.first[:match][:content][:query]
        assert_equal "and", must.first[:match][:content][:operator]
      end

      test "plain query adds display_name should boost" do
        parsed = plain_parsed(terms: %w[bitcoin lightning])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        should = query[:bool][:should]

        assert_equal 1, should.size
        assert_equal "bitcoin lightning", should.first[:match][:display_name][:query]
        assert_equal BuildQuery::DISPLAY_NAME_BOOST, should.first[:match][:display_name][:boost]
      end

      test "plain query has no minimum_should_match" do
        parsed = plain_parsed(terms: %w[bitcoin])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        assert_nil query[:bool][:minimum_should_match]
      end

      # =========================================================================
      # Advanced Queries (Strategy B)
      # =========================================================================

      test "advanced query uses single match for terms plus match_phrase" do
        parsed = advanced_parsed(
          terms: %w[bitcoin],
          phrases: [ "lightning network" ],
          exclusions: [ "scam" ]
        )
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        must = query[:bool][:must]

        assert_equal 2, must.size
        assert_equal "bitcoin", must.first[:match][:content][:query]
        assert_equal "lightning network", must.last[:match_phrase][:content]
      end

      test "advanced query adds display_name should boost for terms" do
        parsed = advanced_parsed(
          terms: %w[bitcoin],
          phrases: [ "lightning network" ]
        )
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        should = query[:bool][:should]

        assert_equal 1, should.size
        assert_equal "bitcoin", should.first[:match][:display_name][:query]
        assert_equal BuildQuery::DISPLAY_NAME_BOOST, should.first[:match][:display_name][:boost]
      end

      test "phrase-only query has no must term match and no display_name boost" do
        parsed = advanced_parsed(phrases: [ "lightning network" ])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        must = query[:bool][:must]

        # Only the match_phrase, no term match
        assert_equal 1, must.size
        assert_equal "lightning network", must.first[:match_phrase][:content]

        # No display_name boost (no terms to boost)
        assert_nil query[:bool][:should]
      end

      test "advanced query includes must_not for exclusions" do
        parsed = advanced_parsed(
          terms: %w[bitcoin],
          exclusions: [ "scam" ],
          excluded_phrases: [ "pump and dump" ]
        )
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        must_not = query[:bool][:must_not]

        assert_equal 2, must_not.size
        assert_equal "scam", must_not.first[:match][:content]
        assert_equal "pump and dump", must_not.last[:match_phrase][:content]
      end

      # =========================================================================
      # Pubkey Queries (Strategy C)
      # =========================================================================

      test "pubkey-only query uses should with minimum_should_match 1" do
        hex = "a" * 64
        parsed = plain_parsed(terms: [], pubkey_terms: [ hex ])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]

        assert_nil query[:bool][:must]
        assert_equal 3, query[:bool][:should].size
        assert_equal 1, query[:bool][:minimum_should_match]
      end

      test "pubkey should clauses include author, content, and tags" do
        hex = "a" * 64
        parsed = plain_parsed(terms: [], pubkey_terms: [ hex ])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        should = result.value![:query][:bool][:should]

        # Author boost
        assert_equal hex, should[0][:term][:pubkey][:value]
        assert_equal BuildQuery::PUBKEY_AUTHOR_BOOST, should[0][:term][:pubkey][:boost]

        # Content mention
        assert_equal hex, should[1][:match][:content][:query]

        # Tag mention
        assert_equal hex, should[2][:term][:tags][:value]
      end

      test "pubkey with terms adds should clauses without minimum_should_match" do
        hex = "a" * 64
        parsed = plain_parsed(terms: %w[bitcoin], pubkey_terms: [ hex ])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]

        assert_equal 1, query[:bool][:must].size
        # 1 display_name boost + 3 pubkey clauses
        assert_equal 4, query[:bool][:should].size
        assert_nil query[:bool][:minimum_should_match]
      end

      # =========================================================================
      # Filter Clauses
      # =========================================================================

      test "filter clauses applied from filter hash" do
        parsed = plain_parsed(terms: %w[bitcoin])
        filter = { kinds: [ 1 ], authors: [ "a" * 64 ], since: 1000, until: 2000 }
        result = BuildQuery.call(parsed_query: parsed, filter:, limit: 50)

        query = result.value![:query]
        filters = query[:bool][:filter]

        assert_equal 4, filters.size
        assert_equal 50, result.value![:size]
      end

      test "tag filters included in filter clauses" do
        parsed = plain_parsed(terms: %w[bitcoin])
        filter = { "#e": [ "event123" ], "#p": [ "pubkey456" ] }
        result = BuildQuery.call(parsed_query: parsed, filter:, limit: 100)

        query = result.value![:query]
        filters = query[:bool][:filter]

        assert_equal 2, filters.size
        assert filters.any? { |f| f[:terms]&.dig(:tags) == [ "event123" ] }
        assert filters.any? { |f| f[:terms]&.dig(:tags) == [ "pubkey456" ] }
      end

      test "empty filter produces no filter clauses" do
        parsed = plain_parsed(terms: %w[bitcoin])
        result = BuildQuery.call(parsed_query: parsed, filter: {}, limit: 100)

        query = result.value![:query]
        assert_nil query[:bool][:filter]
      end

      private

      def plain_parsed(terms: [], pubkey_terms: [])
        {
          terms:,
          phrases: [],
          exclusions: [],
          excluded_phrases: [],
          extensions: {},
          from_authors: [],
          pubkey_terms:,
          query_type: :plain,
          identity_hint: false
        }
      end

      def advanced_parsed(terms: [], phrases: [], exclusions: [], excluded_phrases: [], pubkey_terms: [])
        {
          terms:,
          phrases:,
          exclusions:,
          excluded_phrases:,
          extensions: {},
          from_authors: [],
          pubkey_terms:,
          query_type: :advanced,
          identity_hint: false
        }
      end
    end
  end
end
