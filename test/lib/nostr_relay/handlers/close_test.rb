# frozen_string_literal: true

require "test_helper"

module NostrRelay
  module Handlers
    class CloseTest < ActiveSupport::TestCase
      setup do
        @connection = NostrTestHelpers::MockConnection.new
        NostrRelay::Subscriptions.reset!
        NostrRelay::Subscriptions.register(@connection)
      end

      teardown do
        NostrRelay::Subscriptions.reset!
      end

      test "removes subscription" do
        # Create a subscription first
        NostrRelay::Subscriptions.subscribe(
          connection_id: @connection.id,
          sub_id: "test-sub",
          filters: [ { kinds: [ 1 ] } ]
        )

        # Verify it exists
        subs = NostrRelay::Subscriptions.subscriptions[@connection.id]
        assert subs.key?("test-sub")

        # Close it
        Close.call(connection: @connection, sub_id: "test-sub")

        # Verify it's removed
        assert_not subs.key?("test-sub")
      end

      test "does not send response per NIP-01" do
        NostrRelay::Subscriptions.subscribe(
          connection_id: @connection.id,
          sub_id: "test-sub",
          filters: [ { kinds: [ 1 ] } ]
        )

        Close.call(connection: @connection, sub_id: "test-sub")

        # CLOSE should not send any response
        assert_empty @connection.sent_messages
      end

      test "handles non-existent subscription gracefully" do
        # This should not raise
        assert_nothing_raised do
          Close.call(connection: @connection, sub_id: "non-existent")
        end

        assert_empty @connection.sent_messages
      end

      test "does not affect other subscriptions" do
        # Create two subscriptions
        NostrRelay::Subscriptions.subscribe(
          connection_id: @connection.id,
          sub_id: "sub-1",
          filters: [ { kinds: [ 1 ] } ]
        )
        NostrRelay::Subscriptions.subscribe(
          connection_id: @connection.id,
          sub_id: "sub-2",
          filters: [ { kinds: [ 0 ] } ]
        )

        # Close one
        Close.call(connection: @connection, sub_id: "sub-1")

        # The other should remain
        subs = NostrRelay::Subscriptions.subscriptions[@connection.id]
        assert_not subs.key?("sub-1")
        assert subs.key?("sub-2")
      end
    end
  end
end
