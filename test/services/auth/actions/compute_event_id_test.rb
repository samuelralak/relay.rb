# frozen_string_literal: true

require "test_helper"

module Auth
  module Actions
    class ComputeEventIdTest < ActiveSupport::TestCase
      include NostrTestHelpers

      test "computes event ID from canonical JSON" do
        event = {
          "pubkey" => "a" * 64,
          "created_at" => 1234567890,
          "kind" => 1,
          "tags" => [],
          "content" => "test"
        }

        result = ComputeEventId.call(event:)

        assert result.success?
        assert_equal 64, result.value![:event_id].length
        assert_match(/\A[a-f0-9]+\z/, result.value![:event_id])
      end

      test "produces consistent IDs for same input" do
        event = {
          "pubkey" => "b" * 64,
          "created_at" => 1000000000,
          "kind" => 22242,
          "tags" => [ [ "relay", "wss://test.com" ], [ "challenge", "abc" ] ],
          "content" => ""
        }

        result1 = ComputeEventId.call(event:)
        result2 = ComputeEventId.call(event:)

        assert_equal result1.value![:event_id], result2.value![:event_id]
      end

      test "handles symbol keys" do
        event = {
          pubkey: "c" * 64,
          created_at: 1234567890,
          kind: 1,
          tags: [],
          content: "test"
        }

        result = ComputeEventId.call(event:)

        assert result.success?
        assert_equal 64, result.value![:event_id].length
      end

      test "produces different IDs for different content" do
        base_event = {
          "pubkey" => "d" * 64,
          "created_at" => 1234567890,
          "kind" => 1,
          "tags" => []
        }

        result1 = ComputeEventId.call(event: base_event.merge("content" => "hello"))
        result2 = ComputeEventId.call(event: base_event.merge("content" => "world"))

        assert_not_equal result1.value![:event_id], result2.value![:event_id]
      end
    end
  end
end
