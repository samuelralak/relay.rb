# frozen_string_literal: true

require "test_helper"

module Search
  module Actions
    class ParseQueryTest < ActiveSupport::TestCase
      KNOWN_NPUB = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"
      KNOWN_HEX = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"

      # =========================================================================
      # Basic Query Parsing
      # =========================================================================

      test "parses simple terms" do
        result = ParseQuery.call(query: "bitcoin lightning")

        assert result.success?
        assert_equal %w[bitcoin lightning], result.value![:terms]
      end

      test "parses quoted phrases" do
        result = ParseQuery.call(query: '"lightning network" bitcoin')

        assert result.success?
        assert_equal [ "lightning network" ], result.value![:phrases]
        assert_equal [ "bitcoin" ], result.value![:terms]
      end

      test "parses exclusions" do
        result = ParseQuery.call(query: "bitcoin -scam")

        assert result.success?
        assert_equal [ "bitcoin" ], result.value![:terms]
        assert_equal [ "scam" ], result.value![:exclusions]
      end

      test "parses excluded phrases" do
        result = ParseQuery.call(query: 'bitcoin -"pump and dump"')

        assert result.success?
        assert_equal [ "bitcoin" ], result.value![:terms]
        assert_equal [ "pump and dump" ], result.value![:excluded_phrases]
      end

      test "parses extensions" do
        result = ParseQuery.call(query: "bitcoin include:spam")

        assert result.success?
        assert_equal "spam", result.value![:extensions]["include"]
      end

      # =========================================================================
      # from: Extension
      # =========================================================================

      test "parses from: extension with npub" do
        result = ParseQuery.call(query: "bitcoin from:#{KNOWN_NPUB}")

        assert result.success?
        assert_equal [ "bitcoin" ], result.value![:terms]
        assert_equal [ KNOWN_HEX ], result.value![:from_authors]
      end

      test "parses from: extension with hex pubkey" do
        result = ParseQuery.call(query: "bitcoin from:#{KNOWN_HEX}")

        assert result.success?
        assert_equal [ "bitcoin" ], result.value![:terms]
        assert_equal [ KNOWN_HEX ], result.value![:from_authors]
      end

      test "parses from: extension with multiple comma-separated pubkeys" do
        hex2 = "a" * 64
        result = ParseQuery.call(query: "bitcoin from:#{KNOWN_HEX},#{hex2}")

        assert result.success?
        assert_equal [ KNOWN_HEX, hex2 ], result.value![:from_authors]
      end

      test "ignores invalid pubkeys in from: extension" do
        result = ParseQuery.call(query: "bitcoin from:invalid,#{KNOWN_HEX}")

        assert result.success?
        # Only valid pubkey is included
        assert_equal [ KNOWN_HEX ], result.value![:from_authors]
      end

      test "returns empty array when from: has only invalid pubkeys" do
        result = ParseQuery.call(query: "bitcoin from:invalid")

        assert result.success?
        assert_equal [], result.value![:from_authors]
      end

      test "returns empty array when no from: extension" do
        result = ParseQuery.call(query: "bitcoin")

        assert result.success?
        assert_equal [], result.value![:from_authors]
      end

      # =========================================================================
      # Pubkey Term Detection
      # =========================================================================

      test "extracts npub from terms into pubkey_terms" do
        result = ParseQuery.call(query: KNOWN_NPUB)

        assert result.success?
        assert_equal [ KNOWN_HEX ], result.value![:pubkey_terms]
        assert_empty result.value![:terms]
      end

      test "extracts hex pubkey from terms into pubkey_terms" do
        result = ParseQuery.call(query: KNOWN_HEX)

        assert result.success?
        assert_equal [ KNOWN_HEX ], result.value![:pubkey_terms]
        assert_empty result.value![:terms]
      end

      test "keeps regular terms separate from pubkey_terms" do
        result = ParseQuery.call(query: "bitcoin #{KNOWN_HEX}")

        assert result.success?
        assert_equal [ "bitcoin" ], result.value![:terms]
        assert_equal [ KNOWN_HEX ], result.value![:pubkey_terms]
      end

      test "non-pubkey terms stay in terms" do
        result = ParseQuery.call(query: "bitcoin lightning")

        assert result.success?
        assert_equal %w[bitcoin lightning], result.value![:terms]
        assert_empty result.value![:pubkey_terms]
      end

      # =========================================================================
      # Query Type Classification
      # =========================================================================

      test "classifies simple terms as plain query_type" do
        result = ParseQuery.call(query: "bitcoin lightning")

        assert_equal :plain, result.value![:query_type]
      end

      test "classifies query with phrases as advanced query_type" do
        result = ParseQuery.call(query: '"lightning network" bitcoin')

        assert_equal :advanced, result.value![:query_type]
      end

      test "classifies query with exclusions as advanced query_type" do
        result = ParseQuery.call(query: "bitcoin -scam")

        assert_equal :advanced, result.value![:query_type]
      end

      test "classifies query with excluded phrases as advanced query_type" do
        result = ParseQuery.call(query: 'bitcoin -"pump and dump"')

        assert_equal :advanced, result.value![:query_type]
      end

      test "include:spam does not make query advanced" do
        result = ParseQuery.call(query: "bitcoin include:spam")

        assert_equal :plain, result.value![:query_type]
      end

      test "from: extension does not make query advanced" do
        result = ParseQuery.call(query: "bitcoin from:#{KNOWN_NPUB}")

        assert_equal :plain, result.value![:query_type]
      end

      # =========================================================================
      # Identity Hint
      # =========================================================================

      test "single short term triggers identity_hint" do
        result = ParseQuery.call(query: "fiatjaf")

        assert result.value![:identity_hint]
      end

      test "single term with dots triggers identity_hint" do
        result = ParseQuery.call(query: "hodl.er")

        assert result.value![:identity_hint]
      end

      test "multiple terms do not trigger identity_hint" do
        result = ParseQuery.call(query: "bitcoin lightning")

        refute result.value![:identity_hint]
      end

      test "pubkey term triggers identity_hint" do
        result = ParseQuery.call(query: KNOWN_HEX)

        assert result.value![:identity_hint]
      end

      test "long term does not trigger identity_hint" do
        result = ParseQuery.call(query: "a" * 31)

        refute result.value![:identity_hint]
      end

      test "term with spaces does not trigger identity_hint" do
        result = ParseQuery.call(query: "hello world")

        refute result.value![:identity_hint]
      end

      # =========================================================================
      # Complex Queries
      # =========================================================================

      test "parses complex query with all features" do
        query = %(bitcoin "lightning network" -scam -"pump and dump" from:#{KNOWN_NPUB} include:spam)
        result = ParseQuery.call(query:)

        assert result.success?
        values = result.value!

        assert_equal [ "bitcoin" ], values[:terms]
        assert_equal [ "lightning network" ], values[:phrases]
        assert_equal [ "scam" ], values[:exclusions]
        assert_equal [ "pump and dump" ], values[:excluded_phrases]
        assert_equal [ KNOWN_HEX ], values[:from_authors]
        assert_equal "spam", values[:extensions]["include"]
        assert_empty values[:pubkey_terms]
        assert_equal :advanced, values[:query_type]
      end
    end
  end
end
