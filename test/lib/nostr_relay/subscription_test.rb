# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class SubscriptionTest < ActiveSupport::TestCase
    # =========================================================================
    # Setup
    # =========================================================================

    def create_subscription(filters)
      Subscription.new(sub_id: "test-sub", filters:)
    end

    # =========================================================================
    # matches? with Event Model (uses event.matches_filter?)
    # =========================================================================

    test "matches? delegates to event.matches_filter?" do
      subscription = create_subscription([ { kinds: [ 1 ] } ])
      event = events(:text_note)

      # The subscription should match if ANY filter matches
      assert subscription.matches?(event)
    end

    test "matches? returns false when no filter matches" do
      subscription = create_subscription([ { kinds: [ 9999 ] } ])
      event = events(:text_note)

      assert_not subscription.matches?(event)
    end

    test "matches? returns true if any filter matches (OR logic)" do
      subscription = create_subscription([
        { kinds: [ 9999 ] },  # Won't match
        { kinds: [ 1 ] }      # Will match
      ])
      event = events(:text_note)

      assert subscription.matches?(event)
    end

    # =========================================================================
    # matches_data? with Raw Event Data (ephemeral events)
    # =========================================================================

    def sample_event_data(overrides = {})
      {
        "id" => overrides[:id] || SecureRandom.hex(32),
        "pubkey" => overrides[:pubkey] || "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "created_at" => overrides[:created_at] || Time.now.to_i,
        "kind" => overrides[:kind] || 1,
        "tags" => overrides[:tags] || [],
        "content" => overrides[:content] || "Hello",
        "sig" => SecureRandom.hex(64)
      }
    end

    # -------------------------------------------------------------------------
    # Kind Filtering
    # -------------------------------------------------------------------------

    test "matches_data? filters by kind" do
      subscription = create_subscription([ { "kinds" => [ 1, 7 ] } ])

      assert subscription.matches_data?(sample_event_data(kind: 1))
      assert subscription.matches_data?(sample_event_data(kind: 7))
      assert_not subscription.matches_data?(sample_event_data(kind: 0))
    end

    test "matches_data? matches any kind when not specified" do
      subscription = create_subscription([ {} ])

      assert subscription.matches_data?(sample_event_data(kind: 1))
      assert subscription.matches_data?(sample_event_data(kind: 20000))
    end

    # -------------------------------------------------------------------------
    # Author Filtering
    # -------------------------------------------------------------------------

    test "matches_data? filters by authors" do
      pubkey = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      subscription = create_subscription([ { "authors" => [ pubkey ] } ])

      assert subscription.matches_data?(sample_event_data(pubkey:))
      assert_not subscription.matches_data?(sample_event_data(pubkey: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"))
    end

    # -------------------------------------------------------------------------
    # ID Filtering
    # -------------------------------------------------------------------------

    test "matches_data? filters by ids" do
      event_id = SecureRandom.hex(32)
      subscription = create_subscription([ { "ids" => [ event_id ] } ])

      assert subscription.matches_data?(sample_event_data(id: event_id))
      assert_not subscription.matches_data?(sample_event_data(id: SecureRandom.hex(32)))
    end

    # -------------------------------------------------------------------------
    # Time Range Filtering
    # -------------------------------------------------------------------------

    test "matches_data? filters by since" do
      now = Time.now.to_i
      subscription = create_subscription([ { "since" => now - 3600 } ])

      assert subscription.matches_data?(sample_event_data(created_at: now))
      assert_not subscription.matches_data?(sample_event_data(created_at: now - 7200))
    end

    test "matches_data? filters by until" do
      now = Time.now.to_i
      subscription = create_subscription([ { "until" => now } ])

      assert subscription.matches_data?(sample_event_data(created_at: now - 3600))
      assert_not subscription.matches_data?(sample_event_data(created_at: now + 3600))
    end

    test "matches_data? filters by since and until together" do
      now = Time.now.to_i
      subscription = create_subscription([ {
        "since" => now - 3600,
        "until" => now
      } ])

      assert subscription.matches_data?(sample_event_data(created_at: now - 1800))
      assert_not subscription.matches_data?(sample_event_data(created_at: now - 7200))
      assert_not subscription.matches_data?(sample_event_data(created_at: now + 3600))
    end

    # -------------------------------------------------------------------------
    # Tag Filtering
    # -------------------------------------------------------------------------

    test "matches_data? filters by #e tag" do
      event_id = SecureRandom.hex(32)
      subscription = create_subscription([ { "#e" => [ event_id ] } ])

      assert subscription.matches_data?(sample_event_data(tags: [ [ "e", event_id ] ]))
      assert_not subscription.matches_data?(sample_event_data(tags: [ [ "e", SecureRandom.hex(32) ] ]))
      assert_not subscription.matches_data?(sample_event_data(tags: []))
    end

    test "matches_data? filters by #p tag" do
      pubkey = SecureRandom.hex(32)
      subscription = create_subscription([ { "#p" => [ pubkey ] } ])

      assert subscription.matches_data?(sample_event_data(tags: [ [ "p", pubkey ] ]))
      assert_not subscription.matches_data?(sample_event_data(tags: []))
    end

    test "matches_data? filters by #t tag" do
      subscription = create_subscription([ { "#t" => [ "nostr", "bitcoin" ] } ])

      assert subscription.matches_data?(sample_event_data(tags: [ [ "t", "nostr" ] ]))
      assert subscription.matches_data?(sample_event_data(tags: [ [ "t", "bitcoin" ] ]))
      assert_not subscription.matches_data?(sample_event_data(tags: [ [ "t", "other" ] ]))
    end

    test "matches_data? matches when event has multiple tags and one matches" do
      target_pubkey = SecureRandom.hex(32)
      other_pubkey = SecureRandom.hex(32)
      subscription = create_subscription([ { "#p" => [ target_pubkey ] } ])

      event_data = sample_event_data(tags: [
        [ "p", other_pubkey ],
        [ "p", target_pubkey ],
        [ "t", "nostr" ]
      ])

      assert subscription.matches_data?(event_data)
    end

    # -------------------------------------------------------------------------
    # Complex Filters
    # -------------------------------------------------------------------------

    test "matches_data? requires all filter conditions to match" do
      pubkey = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      subscription = create_subscription([ {
        "kinds" => [ 1 ],
        "authors" => [ pubkey ]
      } ])

      # Both match
      assert subscription.matches_data?(sample_event_data(kind: 1, pubkey:))

      # Kind matches, author doesn't
      assert_not subscription.matches_data?(sample_event_data(kind: 1, pubkey: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"))

      # Author matches, kind doesn't
      assert_not subscription.matches_data?(sample_event_data(kind: 7, pubkey:))
    end

    test "matches_data? with multiple filters uses OR logic" do
      pubkey1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      pubkey2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

      subscription = create_subscription([
        { "authors" => [ pubkey1 ] },
        { "authors" => [ pubkey2 ] }
      ])

      assert subscription.matches_data?(sample_event_data(pubkey: pubkey1))
      assert subscription.matches_data?(sample_event_data(pubkey: pubkey2))
      assert_not subscription.matches_data?(sample_event_data(pubkey: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"))
    end

    # -------------------------------------------------------------------------
    # Edge Cases
    # -------------------------------------------------------------------------

    test "matches_data? handles symbol keys in filter" do
      subscription = create_subscription([ { kinds: [ 1 ] } ])

      assert subscription.matches_data?(sample_event_data(kind: 1))
    end

    test "matches_data? handles symbol keys in event data" do
      subscription = create_subscription([ { "kinds" => [ 1 ] } ])
      event_data = {
        id: SecureRandom.hex(32),
        pubkey: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        created_at: Time.now.to_i,
        kind: 1,
        tags: [],
        content: "Hello",
        sig: SecureRandom.hex(64)
      }

      assert subscription.matches_data?(event_data)
    end

    test "matches_data? handles empty filter (matches all)" do
      subscription = create_subscription([ {} ])

      assert subscription.matches_data?(sample_event_data(kind: 1))
      assert subscription.matches_data?(sample_event_data(kind: 20000))
    end

    test "matches_data? handles malformed tags gracefully" do
      subscription = create_subscription([ { "#e" => [ SecureRandom.hex(32) ] } ])

      # Tags that are not arrays or don't have enough elements
      event_data = sample_event_data(tags: [
        "not-an-array",
        [ "e" ],  # Too short
        nil
      ])

      assert_not subscription.matches_data?(event_data)
    end
  end
end
