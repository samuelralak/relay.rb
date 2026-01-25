# frozen_string_literal: true

require "test_helper"

module NostrRelay
  module Handlers
    class ReqTest < ActiveSupport::TestCase
      setup do
        @connection = NostrTestHelpers::MockConnection.new
        NostrRelay::Subscriptions.reset!
        NostrRelay::Subscriptions.register(@connection)
      end

      teardown do
        NostrRelay::Subscriptions.reset!
      end

      # =========================================================================
      # Successful Subscriptions
      # =========================================================================

      test "creates subscription and sends EOSE" do
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 1 ] } ])

        eose = @connection.sent_messages.find { |m| m[0] == "EOSE" }
        assert_not_nil eose
        assert_equal "test-sub", eose[1]
      end

      test "sends historical events before EOSE" do
        # Create a test event that matches the filter
        event = events(:text_note)

        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 1 ] } ])

        # Should have EVENT messages followed by EOSE
        event_messages = @connection.sent_messages.select { |m| m[0] == "EVENT" }
        eose_messages = @connection.sent_messages.select { |m| m[0] == "EOSE" }

        assert event_messages.any?, "Expected at least one EVENT message"
        assert_equal 1, eose_messages.count
      end

      test "replaces existing subscription with same sub_id" do
        # Create first subscription
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 1 ] } ])
        @connection.clear!

        # Replace with different filter
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 0 ] } ])

        # Should still work (sends EOSE)
        eose = @connection.sent_messages.find { |m| m[0] == "EOSE" }
        assert_not_nil eose
      end

      # =========================================================================
      # Subscription ID Validation
      # =========================================================================

      test "rejects empty subscription id" do
        Req.call(connection: @connection, sub_id: "", filters: [ { kinds: [ 1 ] } ])

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
        assert_includes closed[2], "invalid subscription id"
      end

      test "rejects subscription id that is too long" do
        long_id = "a" * (NostrRelay::Config.max_subid_length + 1)
        Req.call(connection: @connection, sub_id: long_id, filters: [ { kinds: [ 1 ] } ])

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
        assert_includes closed[2], "invalid subscription id"
      end

      test "accepts subscription id at max length" do
        max_id = "a" * NostrRelay::Config.max_subid_length
        Req.call(connection: @connection, sub_id: max_id, filters: [ { kinds: [ 1 ] } ])

        eose = @connection.sent_messages.find { |m| m[0] == "EOSE" }
        assert_not_nil eose
      end

      test "rejects non-string subscription id" do
        Req.call(connection: @connection, sub_id: 123, filters: [ { kinds: [ 1 ] } ])

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
        assert_includes closed[2], "invalid subscription id"
      end

      # =========================================================================
      # Filter Validation
      # =========================================================================

      test "rejects empty filters array" do
        Req.call(connection: @connection, sub_id: "test-sub", filters: [])

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
        assert_includes closed[2], "at least one filter"
      end

      test "rejects too many filters" do
        max_filters = NostrRelay::Config.max_filters
        filters = (max_filters + 1).times.map { { kinds: [ 1 ] } }

        Req.call(connection: @connection, sub_id: "test-sub", filters:)

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
        assert_includes closed[2], "more than"
      end

      test "rejects invalid filter content" do
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { ids: [ "invalid" ] } ])

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
      end

      # =========================================================================
      # Max Subscriptions Limit
      # =========================================================================

      test "enforces max_subscriptions limit" do
        max_subs = NostrRelay::Config.max_subscriptions

        # Create max subscriptions
        max_subs.times do |i|
          Req.call(connection: @connection, sub_id: "sub-#{i}", filters: [ { kinds: [ 1 ] } ])
        end
        @connection.clear!

        # Try to create one more
        Req.call(connection: @connection, sub_id: "sub-overflow", filters: [ { kinds: [ 1 ] } ])

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
        assert_includes closed[2], "too many subscriptions"
      end

      # =========================================================================
      # Filter Query Behavior
      # =========================================================================

      test "filters events by kind" do
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 0 ] } ])

        event_messages = @connection.sent_messages.select { |m| m[0] == "EVENT" }
        event_messages.each do |msg|
          assert_equal 0, msg[2][:kind]
        end
      end

      test "filters events by author" do
        author = events(:text_note).pubkey
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { authors: [ author ] } ])

        event_messages = @connection.sent_messages.select { |m| m[0] == "EVENT" }
        event_messages.each do |msg|
          assert_equal author, msg[2][:pubkey]
        end
      end

      test "multiple filters use OR logic" do
        # Filter for kind 0 OR kind 1
        Req.call(connection: @connection, sub_id: "test-sub", filters: [
          { kinds: [ 0 ] },
          { kinds: [ 1 ] }
        ])

        event_messages = @connection.sent_messages.select { |m| m[0] == "EVENT" }
        kinds = event_messages.map { |m| m[2][:kind] }.uniq

        # Should include both kinds if they exist in fixtures
        assert(kinds.include?(0) || kinds.include?(1))
      end

      test "respects client-specified limit" do
        # Request with limit of 2
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 1 ], limit: 2 } ])

        event_messages = @connection.sent_messages.select { |m| m[0] == "EVENT" }

        # Should return at most 2 events
        assert event_messages.size <= 2
      end

      test "uses default_limit when no limit specified" do
        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 1 ] } ])

        eose = @connection.sent_messages.find { |m| m[0] == "EOSE" }
        assert_not_nil eose
      end

      # =========================================================================
      # Error Handling
      # =========================================================================

      test "handles internal errors gracefully" do
        # Force an error by mocking the repository
        mock_repo = Object.new
        def mock_repo.matching_filters(*)
          raise StandardError, "Database error"
        end

        original_repo = NostrRelay::Config.event_repository
        NostrRelay::Config.event_repository = mock_repo

        Req.call(connection: @connection, sub_id: "test-sub", filters: [ { kinds: [ 1 ] } ])

        closed = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
        assert_not_nil closed
        assert_includes closed[2], "error:"

        NostrRelay::Config.event_repository = original_repo
      end
    end
  end
end
