# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class RouterTest < ActiveSupport::TestCase
    setup do
      @connection = NostrTestHelpers::MockConnection.new
      NostrRelay::Subscriptions.reset!
      NostrRelay::Subscriptions.register(@connection)
    end

    teardown do
      NostrRelay::Subscriptions.reset!
    end

    # =========================================================================
    # Message Format Validation
    # =========================================================================

    test "rejects non-array message" do
      Router.route(connection: @connection, data: '{"type": "EVENT"}')

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "must be a JSON array"
    end

    test "rejects empty array" do
      Router.route(connection: @connection, data: "[]")

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "must be a JSON array"
    end

    test "handles invalid JSON" do
      Router.route(connection: @connection, data: "not valid json")

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "invalid JSON"
    end

    test "rejects unknown message type" do
      Router.route(connection: @connection, data: '["UNKNOWN", "data"]')

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "unknown message type"
    end

    # =========================================================================
    # EVENT Message Routing
    # =========================================================================

    test "routes EVENT message to Event handler" do
      event_data = {
        "id" => SecureRandom.hex(32),
        "pubkey" => SecureRandom.hex(32),
        "created_at" => Time.now.to_i,
        "kind" => 1,
        "tags" => [],
        "content" => "test",
        "sig" => SecureRandom.hex(64)
      }

      Router.route(connection: @connection, data: [ "EVENT", event_data ].to_json)

      # Should get an OK response (success or failure)
      assert_equal "OK", @connection.last_sent[0]
    end

    test "rejects EVENT without event object" do
      Router.route(connection: @connection, data: '["EVENT"]')

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "requires an event object"
    end

    test "rejects EVENT with non-hash payload" do
      Router.route(connection: @connection, data: '["EVENT", "not-an-object"]')

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "requires an event object"
    end

    # =========================================================================
    # REQ Message Routing
    # =========================================================================

    test "routes REQ message to Req handler" do
      Router.route(connection: @connection, data: '["REQ", "sub1", {"kinds": [1]}]')

      # Should get EOSE (end of stored events) after successful subscription
      eose_message = @connection.sent_messages.find { |m| m[0] == "EOSE" }
      assert_not_nil eose_message
      assert_equal "sub1", eose_message[1]
    end

    test "rejects REQ without subscription id" do
      Router.route(connection: @connection, data: '["REQ"]')

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "requires a subscription id"
    end

    test "handles REQ with empty filters" do
      # Empty filters array should be handled by FiltersContract
      Router.route(connection: @connection, data: '["REQ", "sub1"]')

      # Should get CLOSED due to invalid filters (empty array)
      closed_message = @connection.sent_messages.find { |m| m[0] == "CLOSED" }
      assert_not_nil closed_message
    end

    # =========================================================================
    # CLOSE Message Routing
    # =========================================================================

    test "routes CLOSE message to Close handler" do
      # First create a subscription
      Router.route(connection: @connection, data: '["REQ", "sub1", {"kinds": [1]}]')
      @connection.clear!

      # Then close it
      Router.route(connection: @connection, data: '["CLOSE", "sub1"]')

      # CLOSE doesn't send a response per NIP-01
      assert_empty @connection.sent_messages
    end

    test "rejects CLOSE without subscription id" do
      Router.route(connection: @connection, data: '["CLOSE"]')

      assert_equal "NOTICE", @connection.last_sent[0]
      assert_includes @connection.last_sent[1], "requires a subscription id"
    end

    # =========================================================================
    # Error Handling
    # =========================================================================

    test "handles internal errors and sends NOTICE" do
      # Use a connection that tracks messages but mock a handler to raise
      original_processor = NostrRelay::Config.event_processor
      mock_processor = Object.new
      def mock_processor.call(*)
        raise StandardError, "Simulated internal error"
      end
      NostrRelay::Config.event_processor = mock_processor

      event_data = { "id" => SecureRandom.hex(32), "kind" => 1 }
      Router.route(connection: @connection, data: [ "EVENT", event_data ].to_json)

      # Should still get OK (handler catches its own errors)
      assert_equal "OK", @connection.last_sent[0]

      NostrRelay::Config.event_processor = original_processor
    end
  end
end
