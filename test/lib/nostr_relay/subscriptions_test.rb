# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class SubscriptionsTest < ActiveSupport::TestCase
    setup do
      Subscriptions.reset!
      @connection = NostrTestHelpers::MockConnection.new
    end

    teardown do
      Subscriptions.reset!
    end

    # =========================================================================
    # Connection Registration
    # =========================================================================

    test "register adds connection" do
      Subscriptions.register(@connection)

      assert Subscriptions.connections.key?(@connection.id)
      assert_equal @connection, Subscriptions.connections[@connection.id]
    end

    test "unregister removes connection" do
      Subscriptions.register(@connection)
      Subscriptions.unregister(@connection.id)

      assert_not Subscriptions.connections.key?(@connection.id)
    end

    test "unregister removes all subscriptions for connection" do
      Subscriptions.register(@connection)
      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub2", filters: [ { kinds: [ 0 ] } ])

      Subscriptions.unregister(@connection.id)

      assert_not Subscriptions.subscriptions.key?(@connection.id)
    end

    # =========================================================================
    # Subscription Management
    # =========================================================================

    test "subscribe creates new subscription" do
      Subscriptions.register(@connection)

      success, _error = Subscriptions.subscribe(
        connection_id: @connection.id,
        sub_id: "test-sub",
        filters: [ { kinds: [ 1 ] } ]
      )

      assert success
      assert Subscriptions.subscriptions[@connection.id].key?("test-sub")
    end

    test "subscribe returns error when max_subscriptions exceeded" do
      Subscriptions.register(@connection)
      max_subs = NostrRelay::Config.max_subscriptions

      # Create max subscriptions
      max_subs.times do |i|
        Subscriptions.subscribe(
          connection_id: @connection.id,
          sub_id: "sub-#{i}",
          filters: [ { kinds: [ 1 ] } ]
        )
      end

      # Try to create one more
      success, error = Subscriptions.subscribe(
        connection_id: @connection.id,
        sub_id: "overflow-sub",
        filters: [ { kinds: [ 1 ] } ]
      )

      assert_not success
      assert_includes error, "too many subscriptions"
    end

    test "subscribe replaces existing subscription without counting toward limit" do
      Subscriptions.register(@connection)
      max_subs = NostrRelay::Config.max_subscriptions

      # Create max subscriptions
      max_subs.times do |i|
        Subscriptions.subscribe(
          connection_id: @connection.id,
          sub_id: "sub-#{i}",
          filters: [ { kinds: [ 1 ] } ]
        )
      end

      # Replace an existing subscription (should succeed)
      success, _error = Subscriptions.subscribe(
        connection_id: @connection.id,
        sub_id: "sub-0",  # Existing ID
        filters: [ { kinds: [ 7 ] } ]
      )

      assert success
    end

    test "unsubscribe removes subscription" do
      Subscriptions.register(@connection)
      Subscriptions.subscribe(
        connection_id: @connection.id,
        sub_id: "test-sub",
        filters: [ { kinds: [ 1 ] } ]
      )

      Subscriptions.unsubscribe(@connection.id, "test-sub")

      assert_not Subscriptions.subscriptions[@connection.id].key?("test-sub")
    end

    test "unsubscribe handles non-existent subscription" do
      Subscriptions.register(@connection)

      # Should not raise
      assert_nothing_raised do
        Subscriptions.unsubscribe(@connection.id, "non-existent")
      end
    end

    # =========================================================================
    # Broadcasting
    # =========================================================================

    test "broadcast sends to matching subscriptions" do
      conn1 = NostrTestHelpers::MockConnection.new
      conn2 = NostrTestHelpers::MockConnection.new

      Subscriptions.register(conn1)
      Subscriptions.register(conn2)

      # conn1 subscribes to kind 1
      Subscriptions.subscribe(connection_id: conn1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      # conn2 subscribes to kind 7
      Subscriptions.subscribe(connection_id: conn2.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])

      # Broadcast a kind 1 event
      event = events(:text_note)
      Subscriptions.broadcast(event)

      # conn1 should receive it, conn2 should not
      assert conn1.sent_messages.any? { |m| m[0] == "EVENT" }
      assert_not conn2.sent_messages.any? { |m| m[0] == "EVENT" }
    end

    test "broadcast sends to multiple matching subscriptions on same connection" do
      Subscriptions.register(@connection)

      # Same connection, two subscriptions that both match
      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub2", filters: [ { kinds: [ 1 ] } ])

      event = events(:text_note)
      Subscriptions.broadcast(event)

      event_messages = @connection.sent_messages.select { |m| m[0] == "EVENT" }
      sub_ids = event_messages.map { |m| m[1] }

      assert_includes sub_ids, "sub1"
      assert_includes sub_ids, "sub2"
    end

    test "broadcast skips non-matching subscriptions" do
      Subscriptions.register(@connection)

      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub1", filters: [ { kinds: [ 9999 ] } ])

      event = events(:text_note)
      Subscriptions.broadcast(event)

      assert_empty @connection.sent_messages
    end

    # =========================================================================
    # Ephemeral Event Broadcasting
    # =========================================================================

    test "broadcast_ephemeral sends to matching subscriptions" do
      Subscriptions.register(@connection)
      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub1", filters: [ { kinds: [ 20000 ] } ])

      event_data = {
        "id" => SecureRandom.hex(32),
        "pubkey" => SecureRandom.hex(32),
        "created_at" => Time.now.to_i,
        "kind" => 20000,
        "tags" => [],
        "content" => "ephemeral",
        "sig" => SecureRandom.hex(64)
      }

      Subscriptions.broadcast_ephemeral(event_data)

      event_messages = @connection.sent_messages.select { |m| m[0] == "EVENT" }
      assert_equal 1, event_messages.count
      assert_equal "sub1", event_messages.first[1]
    end

    test "broadcast_ephemeral skips non-matching subscriptions" do
      Subscriptions.register(@connection)
      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])

      event_data = {
        "id" => SecureRandom.hex(32),
        "pubkey" => SecureRandom.hex(32),
        "created_at" => Time.now.to_i,
        "kind" => 20000,  # Ephemeral kind, but subscription is for kind 1
        "tags" => [],
        "content" => "ephemeral",
        "sig" => SecureRandom.hex(64)
      }

      Subscriptions.broadcast_ephemeral(event_data)

      assert_empty @connection.sent_messages
    end

    # =========================================================================
    # Dead Connection Cleanup
    # =========================================================================

    test "broadcast cleans up dead connections" do
      # Create a connection that will fail on send
      dead_connection = Object.new
      dead_id = SecureRandom.uuid
      def dead_connection.id
        @dead_id ||= SecureRandom.uuid
      end

      def dead_connection.send_event(*, **)
        raise StandardError, "Connection closed"
      end

      # Manually register the dead connection
      Subscriptions.connections[dead_connection.id] = dead_connection
      Subscriptions.subscriptions[dead_connection.id]["sub1"] = Subscription.new(
        sub_id: "sub1",
        filters: [ { kinds: [ 1 ] } ]
      )

      # Broadcast should trigger cleanup
      event = events(:text_note)
      Subscriptions.broadcast(event)

      # Dead connection should be removed
      assert_not Subscriptions.connections.key?(dead_connection.id)
    end

    # =========================================================================
    # Thread Safety
    # =========================================================================

    test "uses concurrent data structures" do
      assert_kind_of Concurrent::Hash, Subscriptions.connections
      assert_kind_of Concurrent::Hash, Subscriptions.subscriptions
    end

    # =========================================================================
    # Reset
    # =========================================================================

    test "reset! clears all state" do
      Subscriptions.register(@connection)
      Subscriptions.subscribe(connection_id: @connection.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])

      Subscriptions.reset!

      assert_empty Subscriptions.connections
      assert_empty Subscriptions.subscriptions
    end
  end
end
