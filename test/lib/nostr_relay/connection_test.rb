# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class ConnectionTest < ActiveSupport::TestCase
    setup do
      @ws = NostrTestHelpers::MockWebSocket.new
      @connection = Connection.new(@ws)
      NostrRelay::Subscriptions.reset!
    end

    teardown do
      NostrRelay::Subscriptions.reset!
    end

    # =========================================================================
    # Initialization
    # =========================================================================

    test "generates unique connection ID" do
      conn1 = Connection.new(NostrTestHelpers::MockWebSocket.new)
      conn2 = Connection.new(NostrTestHelpers::MockWebSocket.new)

      assert_not_nil conn1.id
      assert_not_nil conn2.id
      assert_not_equal conn1.id, conn2.id
    end

    # =========================================================================
    # Lifecycle: on_open
    # =========================================================================

    test "registers with Subscriptions on open" do
      @connection.on_open

      assert NostrRelay::Subscriptions.connections.key?(@connection.id)
    end

    # =========================================================================
    # Lifecycle: on_close
    # =========================================================================

    test "unregisters from Subscriptions on close" do
      @connection.on_open
      assert NostrRelay::Subscriptions.connections.key?(@connection.id)

      @connection.on_close(1000, "Normal closure")

      assert_not NostrRelay::Subscriptions.connections.key?(@connection.id)
    end

    test "removes all subscriptions on close" do
      @connection.on_open
      NostrRelay::Subscriptions.subscribe(
        connection_id: @connection.id,
        sub_id: "test-sub",
        filters: [ { kinds: [ 1 ] } ]
      )

      @connection.on_close(1000, "Normal closure")

      assert_not NostrRelay::Subscriptions.subscriptions.key?(@connection.id)
    end

    # =========================================================================
    # Message Size Limit
    # =========================================================================

    test "rejects messages exceeding max_message_length" do
      @connection.on_open
      large_message = "a" * (NostrRelay::Config.max_message_length + 1)

      @connection.on_message(large_message)

      parsed = @ws.last_message_parsed
      assert_equal "NOTICE", parsed[0]
      assert_includes parsed[1], "too large"
    end

    test "accepts messages within max_message_length" do
      @connection.on_open
      valid_message = '["REQ", "sub1", {"kinds": [1]}]'

      @connection.on_message(valid_message)

      # Should process the message (get EOSE or CLOSED)
      parsed = @ws.last_message_parsed
      assert_includes [ "EOSE", "CLOSED" ], parsed[0]
    end

    # =========================================================================
    # Outbound Message Formatting
    # =========================================================================

    test "send_event formats correctly" do
      event_data = { "id" => "abc", "kind" => 1 }
      @connection.send_event("sub1", event_data)

      parsed = @ws.last_message_parsed
      assert_equal [ "EVENT", "sub1", event_data ], parsed
    end

    test "send_ok formats correctly for success" do
      @connection.send_ok("event123", true, "")

      parsed = @ws.last_message_parsed
      assert_equal [ "OK", "event123", true, "" ], parsed
    end

    test "send_ok formats correctly for failure" do
      @connection.send_ok("event123", false, "invalid: bad signature")

      parsed = @ws.last_message_parsed
      assert_equal [ "OK", "event123", false, "invalid: bad signature" ], parsed
    end

    test "send_eose formats correctly" do
      @connection.send_eose("sub1")

      parsed = @ws.last_message_parsed
      assert_equal [ "EOSE", "sub1" ], parsed
    end

    test "send_closed formats correctly" do
      @connection.send_closed("sub1", "error: internal error")

      parsed = @ws.last_message_parsed
      assert_equal [ "CLOSED", "sub1", "error: internal error" ], parsed
    end

    test "send_notice formats correctly" do
      @connection.send_notice("Hello from relay")

      parsed = @ws.last_message_parsed
      assert_equal [ "NOTICE", "Hello from relay" ], parsed
    end

    # =========================================================================
    # Error Handling
    # =========================================================================

    test "handles send errors gracefully" do
      broken_ws = Object.new
      def broken_ws.send(*)
        raise StandardError, "Connection lost"
      end

      connection = Connection.new(broken_ws)

      # Should not raise
      assert_nothing_raised do
        connection.send_notice("Test message")
      end
    end
  end
end
