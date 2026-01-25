# frozen_string_literal: true

require "test_helper"

module NostrRelay
  module Contracts
    class FilterContractTest < ActiveSupport::TestCase
      # =========================================================================
      # Valid Filters
      # =========================================================================

      test "accepts empty filter" do
        result = FilterContract.new.call({})

        assert result.success?
      end

      test "accepts filter with valid ids" do
        result = FilterContract.new.call({
          ids: [ SecureRandom.hex(32), SecureRandom.hex(32) ]
        })

        assert result.success?
      end

      test "accepts filter with valid authors" do
        result = FilterContract.new.call({
          authors: [ SecureRandom.hex(32) ]
        })

        assert result.success?
      end

      test "accepts filter with valid kinds" do
        result = FilterContract.new.call({
          kinds: [ 0, 1, 3, 7 ]
        })

        assert result.success?
      end

      test "accepts filter with since and until" do
        result = FilterContract.new.call({
          since: Time.now.to_i - 3600,
          until: Time.now.to_i
        })

        assert result.success?
      end

      test "accepts filter with valid limit" do
        result = FilterContract.new.call({
          limit: 100
        })

        assert result.success?
      end

      test "accepts filter with valid #e tag filter" do
        result = FilterContract.new.call({
          "#e": [ SecureRandom.hex(32) ]
        })

        assert result.success?
      end

      test "accepts filter with valid #p tag filter" do
        result = FilterContract.new.call({
          "#p": [ SecureRandom.hex(32) ]
        })

        assert result.success?
      end

      test "accepts filter with #t tag filter (any string)" do
        result = FilterContract.new.call({
          "#t": [ "nostr", "bitcoin" ]
        })

        assert result.success?
      end

      test "accepts complex filter with multiple fields" do
        result = FilterContract.new.call({
          ids: [ SecureRandom.hex(32) ],
          authors: [ SecureRandom.hex(32) ],
          kinds: [ 1, 7 ],
          since: Time.now.to_i - 3600,
          until: Time.now.to_i,
          limit: 50,
          "#p": [ SecureRandom.hex(32) ]
        })

        assert result.success?
      end

      # =========================================================================
      # Invalid IDs
      # =========================================================================

      test "rejects ids that are not 64 hex chars" do
        result = FilterContract.new.call({
          ids: [ "short" ]
        })

        assert result.failure?
        assert result.errors[:ids].present?
      end

      test "accepts ids with uppercase hex (case insensitive)" do
        result = FilterContract.new.call({
          ids: [ "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" ]
        })

        # Note: Current implementation is case-insensitive
        assert result.success?
      end

      # =========================================================================
      # Invalid Authors
      # =========================================================================

      test "rejects authors that are not 64 hex chars" do
        result = FilterContract.new.call({
          authors: [ "invalid" ]
        })

        assert result.failure?
        assert result.errors[:authors].present?
      end

      # =========================================================================
      # Invalid Limit
      # =========================================================================

      test "rejects limit exceeding max_limit" do
        max_limit = NostrRelay::Config.max_limit
        result = FilterContract.new.call({
          limit: max_limit + 1
        })

        assert result.failure?
        assert result.errors[:limit].present?
      end

      test "accepts limit at max_limit" do
        max_limit = NostrRelay::Config.max_limit
        result = FilterContract.new.call({
          limit: max_limit
        })

        assert result.success?
      end

      # =========================================================================
      # Tag Filters (#e, #p, #t)
      # Note: Tag filter validation for #e and #p is attempted in the contract
      # via values.data, but dry-validation may filter unschema'd keys.
      # These tests verify current behavior.
      # =========================================================================

      test "accepts #e with uppercase hex (case insensitive)" do
        result = FilterContract.new.call({
          "#e": [ "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" ]
        })

        # Note: Current implementation is case-insensitive
        assert result.success?
      end
    end

    class FiltersContractTest < ActiveSupport::TestCase
      # =========================================================================
      # Valid Filters Array
      # =========================================================================

      test "accepts single valid filter" do
        result = FiltersContract.new.call({
          filters: [ { kinds: [ 1 ] } ]
        })

        assert result.success?
      end

      test "accepts multiple valid filters" do
        result = FiltersContract.new.call({
          filters: [
            { kinds: [ 1 ] },
            { authors: [ SecureRandom.hex(32) ] }
          ]
        })

        assert result.success?
      end

      # =========================================================================
      # Invalid Filters Array
      # =========================================================================

      test "rejects empty filters array" do
        result = FiltersContract.new.call({
          filters: []
        })

        assert result.failure?
        assert result.errors[:filters].any? { |e| e.include?("at least one filter") }
      end

      test "rejects too many filters" do
        max_filters = NostrRelay::Config.max_filters
        filters = (max_filters + 1).times.map { { kinds: [ 1 ] } }

        result = FiltersContract.new.call({ filters: })

        assert result.failure?
        assert result.errors[:filters].any? { |e| e.include?("more than") }
      end

      test "accepts filters at max_filters limit" do
        max_filters = NostrRelay::Config.max_filters
        filters = max_filters.times.map { { kinds: [ 1 ] } }

        result = FiltersContract.new.call({ filters: })

        assert result.success?
      end

      test "rejects array with invalid filter" do
        result = FiltersContract.new.call({
          filters: [
            { kinds: [ 1 ] },
            { ids: [ "invalid" ] }
          ]
        })

        assert result.failure?
        assert result.errors[:filters].present?
      end
    end
  end
end
