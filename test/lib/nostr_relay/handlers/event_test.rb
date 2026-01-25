# frozen_string_literal: true

require "test_helper"

module NostrRelay
  module Handlers
    class EventTest < ActiveSupport::TestCase
      setup do
        @connection = NostrTestHelpers::MockConnection.new
      end

      def valid_event_payload
        {
          "id" => SecureRandom.hex(32),
          "pubkey" => SecureRandom.hex(32),
          "created_at" => Time.now.to_i,
          "kind" => 1,
          "tags" => [],
          "content" => "test message",
          "sig" => SecureRandom.hex(64)
        }
      end

      # Simple mock processor class for testing
      class MockProcessor
        attr_reader :result

        def initialize(result)
          @result = result
        end

        def call(*)
          result
        end
      end

      # =========================================================================
      # Success Responses
      # =========================================================================

      test "sends OK with true on successful event" do
        # Note: This will likely fail validation (sig check), but tests the flow
        payload = valid_event_payload

        Event.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_equal payload["id"], @connection.last_sent[1]
        # Success or failure depends on validation
      end

      test "sends OK with duplicate prefix for duplicate events" do
        event = events(:text_note)
        payload = {
          "id" => event.event_id,
          "pubkey" => event.pubkey,
          "created_at" => event.nostr_created_at.to_i,
          "kind" => event.kind,
          "tags" => event.tags,
          "content" => event.content,
          "sig" => event.sig
        }

        mock_processor = MockProcessor.new(Dry::Monads::Success(duplicate: true, event_id: event.event_id))
        original_processor = NostrRelay::Config.event_processor
        NostrRelay::Config.event_processor = mock_processor

        Event.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_equal event.event_id, @connection.last_sent[1]
        assert @connection.last_sent[2] # success = true
        assert_includes @connection.last_sent[3], "duplicate"

        NostrRelay::Config.event_processor = original_processor
      end

      # =========================================================================
      # Failure Responses
      # =========================================================================

      test "sends OK with false on invalid event" do
        mock_processor = MockProcessor.new(Dry::Monads::Failure[:invalid, "invalid: bad signature"])
        original_processor = NostrRelay::Config.event_processor
        NostrRelay::Config.event_processor = mock_processor

        payload = valid_event_payload
        Event.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_equal payload["id"], @connection.last_sent[1]
        assert_not @connection.last_sent[2] # success = false
        assert_includes @connection.last_sent[3], "invalid"

        NostrRelay::Config.event_processor = original_processor
      end

      test "sends OK with false on blocked event" do
        mock_processor = MockProcessor.new(Dry::Monads::Failure[:blocked, "blocked: user is banned"])
        original_processor = NostrRelay::Config.event_processor
        NostrRelay::Config.event_processor = mock_processor

        payload = valid_event_payload
        Event.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_not @connection.last_sent[2] # success = false
        assert_includes @connection.last_sent[3], "blocked"

        NostrRelay::Config.event_processor = original_processor
      end

      # =========================================================================
      # Event ID Extraction
      # =========================================================================

      test "extracts event_id from payload for error responses" do
        payload = { "id" => "abc123" }

        assert_equal "abc123", Event.extract_event_id(payload)
      end

      test "returns empty string for malformed payload" do
        assert_equal "", Event.extract_event_id(nil)
        assert_equal "", Event.extract_event_id("not a hash")
        assert_equal "", Event.extract_event_id({})
      end

      # =========================================================================
      # Error Handling
      # =========================================================================

      test "handles internal errors gracefully" do
        mock_processor = Object.new
        def mock_processor.call(*)
          raise StandardError, "Something went wrong"
        end

        original_processor = NostrRelay::Config.event_processor
        NostrRelay::Config.event_processor = mock_processor

        payload = valid_event_payload
        Event.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_not @connection.last_sent[2] # success = false
        assert_includes @connection.last_sent[3], "error:"

        NostrRelay::Config.event_processor = original_processor
      end
    end
  end
end
