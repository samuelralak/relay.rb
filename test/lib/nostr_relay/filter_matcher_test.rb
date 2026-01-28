# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class FilterMatcherTest < ActiveSupport::TestCase
    include NostrTestHelpers

    def event_hash(kind: 1, pubkey: HEX_64, **overrides)
      {
        "id" => unique_hex(64),
        "pubkey" => pubkey,
        "created_at" => Time.now.to_i,
        "kind" => kind,
        "tags" => [],
        "content" => "test content",
        "sig" => unique_hex(128)
      }.merge(overrides.transform_keys(&:to_s))
    end

    # =======================================================================
    # NIP-42: Auth Events (Kind 22242) Never Match
    # =======================================================================

    test "auth events (kind 22242) never match any filter" do
      auth_event = event_hash(kind: Events::Kinds::AUTH)

      # Even with a filter that explicitly includes kind 22242
      filters = [ { "kinds" => [ Events::Kinds::AUTH ] } ]

      assert_not FilterMatcher.matches?(filters, auth_event)
    end

    test "auth events do not match empty filter" do
      auth_event = event_hash(kind: Events::Kinds::AUTH)
      filters = [ {} ]

      assert_not FilterMatcher.matches?(filters, auth_event)
    end

    test "auth events do not match wildcard kinds filter" do
      auth_event = event_hash(kind: Events::Kinds::AUTH)
      filters = [ { "kinds" => (20_000...30_000).to_a } ]

      assert_not FilterMatcher.matches?(filters, auth_event)
    end

    # =======================================================================
    # Regular Events Still Match
    # =======================================================================

    test "regular events match appropriate filters" do
      event = event_hash(kind: 1)
      filters = [ { "kinds" => [ 1 ] } ]

      assert FilterMatcher.matches?(filters, event)
    end

    test "empty filter matches regular events" do
      event = event_hash(kind: 1)
      filters = [ {} ]

      assert FilterMatcher.matches?(filters, event)
    end

    # =======================================================================
    # Kind Filtering
    # =======================================================================

    test "matches event with correct kind" do
      event = event_hash(kind: 1)
      filters = [ { "kinds" => [ 1, 2, 3 ] } ]

      assert FilterMatcher.matches?(filters, event)
    end

    test "does not match event with wrong kind" do
      event = event_hash(kind: 5)
      filters = [ { "kinds" => [ 1, 2, 3 ] } ]

      assert_not FilterMatcher.matches?(filters, event)
    end

    # =======================================================================
    # Author Filtering
    # =======================================================================

    test "matches event with correct author" do
      event = event_hash(pubkey: HEX_64)
      filters = [ { "authors" => [ HEX_64 ] } ]

      assert FilterMatcher.matches?(filters, event)
    end

    test "does not match event with wrong author" do
      event = event_hash(pubkey: HEX_64)
      filters = [ { "authors" => [ HEX_64_ALT ] } ]

      assert_not FilterMatcher.matches?(filters, event)
    end

    # =======================================================================
    # ID Filtering
    # =======================================================================

    test "matches event with correct id" do
      event_id = unique_hex(64)
      event = event_hash.merge("id" => event_id)
      filters = [ { "ids" => [ event_id ] } ]

      assert FilterMatcher.matches?(filters, event)
    end

    # =======================================================================
    # Timestamp Filtering
    # =======================================================================

    test "matches event within time range" do
      now = Time.now.to_i
      event = event_hash.merge("created_at" => now)
      filters = [ { "since" => now - 60, "until" => now + 60 } ]

      assert FilterMatcher.matches?(filters, event)
    end

    test "does not match event before since" do
      now = Time.now.to_i
      event = event_hash.merge("created_at" => now - 120)
      filters = [ { "since" => now } ]

      assert_not FilterMatcher.matches?(filters, event)
    end

    test "does not match event after until" do
      now = Time.now.to_i
      event = event_hash.merge("created_at" => now + 120)
      filters = [ { "until" => now } ]

      assert_not FilterMatcher.matches?(filters, event)
    end

    # =======================================================================
    # Tag Filtering
    # =======================================================================

    test "matches event with correct tag" do
      event = event_hash.merge("tags" => [ [ "e", HEX_64 ] ])
      filters = [ { "#e" => [ HEX_64 ] } ]

      assert FilterMatcher.matches?(filters, event)
    end

    test "does not match event without required tag" do
      event = event_hash.merge("tags" => [])
      filters = [ { "#e" => [ HEX_64 ] } ]

      assert_not FilterMatcher.matches?(filters, event)
    end

    # =======================================================================
    # Multiple Filters (OR logic)
    # =======================================================================

    test "matches if any filter matches (OR logic)" do
      event = event_hash(kind: 1)
      filters = [
        { "kinds" => [ 999 ] },  # Does not match
        { "kinds" => [ 1 ] }     # Matches
      ]

      assert FilterMatcher.matches?(filters, event)
    end

    test "does not match if no filters match" do
      event = event_hash(kind: 1)
      filters = [
        { "kinds" => [ 999 ] },
        { "kinds" => [ 888 ] }
      ]

      assert_not FilterMatcher.matches?(filters, event)
    end
  end
end
