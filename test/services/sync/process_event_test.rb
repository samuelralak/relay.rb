# frozen_string_literal: true

require "test_helper"

module Sync
  class ProcessEventTest < ActiveSupport::TestCase
    # =========================================================================
    # Test Data
    # =========================================================================

    def valid_event_data(overrides = {})
      {
        id: overrides[:id] || SecureRandom.hex(32),
        pubkey: SecureRandom.hex(32),
        created_at: Time.current.to_i,
        kind: 1,
        tags: [],
        content: "Hello, Nostr!",
        sig: SecureRandom.hex(64)
      }.merge(overrides)
    end

    # =========================================================================
    # Successful Processing
    # =========================================================================

    test "creates event from valid event data" do
      event_data = valid_event_data

      assert_difference "Event.count", 1 do
        result = ProcessEvent.call(event_data: event_data)

        assert result[:success], "Expected success but got: #{result.inspect}"
        assert_equal event_data[:id], result[:event_id]
      end
    end

    test "saves all event attributes correctly" do
      event_data = valid_event_data(
        content: "Test content",
        kind: 7,
        tags: [["e", "a" * 64]]
      )

      ProcessEvent.call(event_data: event_data)

      event = Event.find_by(event_id: event_data[:id])
      assert_not_nil event
      assert_equal event_data[:pubkey], event.pubkey
      assert_equal event_data[:kind], event.kind
      assert_equal event_data[:content], event.content
      assert_equal event_data[:sig], event.sig
    end

    test "handles string keys in event data" do
      event_data = {
        "id" => SecureRandom.hex(32),
        "pubkey" => SecureRandom.hex(32),
        "created_at" => Time.current.to_i,
        "kind" => 1,
        "tags" => [],
        "content" => "String keys work",
        "sig" => SecureRandom.hex(64)
      }

      result = ProcessEvent.call(event_data: event_data)

      assert result[:success]
      assert Event.exists?(event_id: event_data["id"])
    end

    test "accepts optional source_relay parameter" do
      event_data = valid_event_data

      result = ProcessEvent.call(
        event_data: event_data,
        source_relay: "wss://relay.example.com"
      )

      assert result[:success]
    end

    # =========================================================================
    # Duplicate Handling
    # =========================================================================

    test "skips duplicate events" do
      event_data = valid_event_data

      # Create the event first
      first_result = ProcessEvent.call(event_data: event_data)
      assert first_result[:success]

      # Try to create again
      assert_no_difference "Event.count" do
        result = ProcessEvent.call(event_data: event_data)

        assert result[:skipped]
        assert_equal "duplicate", result[:reason]
      end
    end

    test "duplicate check uses event_id only" do
      event_data = valid_event_data
      ProcessEvent.call(event_data: event_data)

      # Same event_id but different content should be skipped
      duplicate_data = event_data.merge(content: "Different content")

      result = ProcessEvent.call(event_data: duplicate_data)

      assert result[:skipped]
      assert_equal "duplicate", result[:reason]
    end

    # =========================================================================
    # Validation Errors
    # =========================================================================

    test "returns error for invalid pubkey" do
      invalid_data = valid_event_data(pubkey: "too_short")

      result = ProcessEvent.call(event_data: invalid_data)

      assert_not result[:success]
      assert_not result[:skipped]
      assert result[:error].present?
    end

    test "returns error for invalid signature" do
      invalid_data = valid_event_data(sig: "invalid")

      result = ProcessEvent.call(event_data: invalid_data)

      assert_not result[:success]
      assert result[:error].present?
    end

    # =========================================================================
    # Edge Cases
    # =========================================================================

    test "handles empty tags array" do
      event_data = valid_event_data(tags: [])

      result = ProcessEvent.call(event_data: event_data)

      assert result[:success]
      event = Event.find_by(event_id: event_data[:id])
      assert_equal [], event.tags
    end

    test "handles empty content string" do
      event_data = valid_event_data(content: "")

      result = ProcessEvent.call(event_data: event_data)

      assert result[:success]
      event = Event.find_by(event_id: event_data[:id])
      assert_equal "", event.content
    end

    test "defaults to empty string when content is nil" do
      event_data = valid_event_data.except(:content)

      result = ProcessEvent.call(event_data: event_data)

      assert result[:success]
      event = Event.find_by(event_id: event_data[:id])
      assert_equal "", event.content
    end

    test "defaults to empty array when tags is nil" do
      event_data = valid_event_data.except(:tags)

      result = ProcessEvent.call(event_data: event_data)

      assert result[:success]
      event = Event.find_by(event_id: event_data[:id])
      assert_equal [], event.tags
    end
  end
end
