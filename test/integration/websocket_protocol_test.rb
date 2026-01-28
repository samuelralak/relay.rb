# frozen_string_literal: true

require "test_helper"

# End-to-end integration tests for the Nostr WebSocket protocol.
# Tests the full flow from raw WebSocket messages through to responses.
class WebSocketProtocolTest < ActiveSupport::TestCase
  setup do
    @ws = NostrTestHelpers::MockWebSocket.new
    @connection = NostrRelay::Connection.new(@ws)
    NostrRelay::Subscriptions.reset!
    # Force EM.reactor_running? to return false for synchronous send in tests
    @original_reactor_running = EM.method(:reactor_running?)
    EM.define_singleton_method(:reactor_running?) do false end
    @connection.on_open
  end

  teardown do
    NostrRelay::Subscriptions.reset!
    # Restore original EM.reactor_running?
    EM.define_singleton_method(:reactor_running?, @original_reactor_running) if @original_reactor_running
  end

  # ===========================================================================
  # NIP-01: Basic Protocol
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # REQ/EOSE Flow
  # ---------------------------------------------------------------------------

  test "REQ followed by EOSE for valid subscription" do
    @connection.on_message('["REQ", "my-sub", {"kinds": [1]}]')

    messages = parsed_messages
    eose = messages.find { |m| m[0] == "EOSE" }

    assert_not_nil eose, "Expected EOSE message"
    assert_equal "my-sub", eose[1]
  end

  test "REQ returns historical events before EOSE" do
    # Assuming fixtures have kind 1 events
    @connection.on_message('["REQ", "my-sub", {"kinds": [1]}]')

    messages = parsed_messages
    event_messages = messages.select { |m| m[0] == "EVENT" }
    eose_index = messages.index { |m| m[0] == "EOSE" }

    # All EVENT messages should come before EOSE
    event_messages.each do |event_msg|
      event_index = messages.index(event_msg)
      assert event_index < eose_index, "EVENT should come before EOSE"
    end
  end

  test "REQ with multiple filters uses OR logic" do
    @connection.on_message('["REQ", "my-sub", {"kinds": [0]}, {"kinds": [1]}]')

    messages = parsed_messages
    event_messages = messages.select { |m| m[0] == "EVENT" }
    kinds = event_messages.map { |m| m[2]["kind"] }.uniq

    # Should include events of kind 0 OR kind 1
    assert(kinds.any? { |k| [ 0, 1 ].include?(k) })
  end

  # ---------------------------------------------------------------------------
  # CLOSE Flow
  # ---------------------------------------------------------------------------

  test "CLOSE removes subscription silently" do
    @connection.on_message('["REQ", "my-sub", {"kinds": [1]}]')
    @ws.clear!

    @connection.on_message('["CLOSE", "my-sub"]')

    # CLOSE should not produce any output
    assert_empty @ws.messages
  end

  test "subscription no longer receives events after CLOSE" do
    @connection.on_message('["REQ", "my-sub", {"kinds": [1]}]')
    @ws.clear!

    @connection.on_message('["CLOSE", "my-sub"]')

    # Broadcast an event
    event = events(:text_note)
    NostrRelay::Subscriptions.broadcast(event)

    # Should not receive any events
    assert_empty @ws.messages
  end

  # ---------------------------------------------------------------------------
  # EVENT Flow
  # ---------------------------------------------------------------------------

  test "EVENT returns OK with event_id on success" do
    # This will fail validation but tests the format
    event_data = {
      "id" => SecureRandom.hex(32),
      "pubkey" => SecureRandom.hex(32),
      "created_at" => Time.now.to_i,
      "kind" => 1,
      "tags" => [],
      "content" => "Hello Nostr!",
      "sig" => SecureRandom.hex(64)
    }

    @connection.on_message([ "EVENT", event_data ].to_json)

    messages = parsed_messages
    ok = messages.find { |m| m[0] == "OK" }

    assert_not_nil ok, "Expected OK message"
    assert_equal event_data["id"], ok[1]
  end

  # ===========================================================================
  # NIP-01: Error Handling
  # ===========================================================================

  test "invalid JSON returns NOTICE with error" do
    @connection.on_message("not valid json")

    messages = parsed_messages
    notice = messages.find { |m| m[0] == "NOTICE" }

    assert_not_nil notice
    assert_includes notice[1], "invalid JSON"
  end

  test "unknown message type returns NOTICE" do
    @connection.on_message('["UNKNOWN", "data"]')

    messages = parsed_messages
    notice = messages.find { |m| m[0] == "NOTICE" }

    assert_not_nil notice
    assert_includes notice[1], "unknown message type"
  end

  test "non-array message returns NOTICE" do
    @connection.on_message('{"type": "EVENT"}')

    messages = parsed_messages
    notice = messages.find { |m| m[0] == "NOTICE" }

    assert_not_nil notice
    assert_includes notice[1], "must be a JSON array"
  end

  # ===========================================================================
  # NIP-01: Limits (integration-level verification)
  # Note: Detailed validation tests are in req_test.rb and connection_test.rb
  # ===========================================================================

  test "subscription limits are enforced end-to-end" do
    max_subs = NostrRelay::Config.max_subscriptions

    # Create max subscriptions
    max_subs.times do |i|
      @connection.on_message(%Q(["REQ", "sub-#{i}", {"kinds": [1]}]))
    end
    @ws.clear!

    # Try to create one more - should get CLOSED
    @connection.on_message('["REQ", "overflow", {"kinds": [1]}]')

    messages = parsed_messages
    closed = messages.find { |m| m[0] == "CLOSED" }

    assert_not_nil closed
    assert_includes closed[2], "too many subscriptions"
  end

  # ===========================================================================
  # Live Event Delivery
  # ===========================================================================

  test "new events broadcast to matching subscriptions" do
    @connection.on_message('["REQ", "my-sub", {"kinds": [1]}]')
    @ws.clear!

    # Broadcast a new event
    event = events(:text_note)
    NostrRelay::Subscriptions.broadcast(event)

    messages = parsed_messages
    event_msg = messages.find { |m| m[0] == "EVENT" && m[1] == "my-sub" }

    assert_not_nil event_msg
    assert_equal event.event_id, event_msg[2]["id"]
  end

  test "events not broadcast to non-matching subscriptions" do
    @connection.on_message('["REQ", "my-sub", {"kinds": [9999]}]')
    @ws.clear!

    # Broadcast a kind 1 event
    event = events(:text_note)
    NostrRelay::Subscriptions.broadcast(event)

    messages = parsed_messages
    event_msgs = messages.select { |m| m[0] == "EVENT" }

    assert_empty event_msgs
  end

  test "multiple subscriptions receive same event" do
    @connection.on_message('["REQ", "sub1", {"kinds": [1]}]')
    @connection.on_message('["REQ", "sub2", {"kinds": [1]}]')
    @ws.clear!

    # Broadcast a new event
    event = events(:text_note)
    NostrRelay::Subscriptions.broadcast(event)

    messages = parsed_messages
    sub_ids = messages.select { |m| m[0] == "EVENT" }.map { |m| m[1] }

    assert_includes sub_ids, "sub1"
    assert_includes sub_ids, "sub2"
  end

  # ===========================================================================
  # Connection Lifecycle
  # ===========================================================================

  test "on_close cleans up all subscriptions" do
    @connection.on_message('["REQ", "sub1", {"kinds": [1]}]')
    @connection.on_message('["REQ", "sub2", {"kinds": [0]}]')

    @connection.on_close(1000, "Normal closure")

    # Connection should be unregistered
    assert_not NostrRelay::Subscriptions.connections.key?(@connection.id)
    assert_not NostrRelay::Subscriptions.subscriptions.key?(@connection.id)
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  private

  def parsed_messages
    @ws.messages.map { |m| JSON.parse(m) }
  end
end
