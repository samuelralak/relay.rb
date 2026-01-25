# frozen_string_literal: true

require "test_helper"

module NostrRelay
  module Contracts
    class EventContractTest < ActiveSupport::TestCase
      # =========================================================================
      # Test Data
      # =========================================================================

      def valid_event(overrides = {})
        {
          id: overrides[:id] || SecureRandom.hex(32),
          pubkey: overrides[:pubkey] || SecureRandom.hex(32),
          created_at: overrides[:created_at] || Time.current.to_i,
          kind: overrides[:kind] || 1,
          tags: overrides[:tags] || [],
          content: overrides[:content] || "Hello, Nostr!",
          sig: overrides[:sig] || SecureRandom.hex(64)
        }
      end

      # =========================================================================
      # NIP-40: Expiration Validation
      # =========================================================================

      test "rejects events with past expiration timestamp" do
        past_expiration = (Time.now.to_i - 3600).to_s  # 1 hour ago
        event_data = valid_event(tags: [ [ "expiration", past_expiration ] ])

        result = EventContract.new.call(event_data)

        assert result.failure?
        assert result.errors[:tags].any? { |e| e.include?("expired") }
      end

      test "accepts events with future expiration timestamp" do
        future_expiration = (Time.now.to_i + 3600).to_s  # 1 hour from now
        event_data = valid_event(tags: [ [ "expiration", future_expiration ] ])

        result = EventContract.new.call(event_data)

        # Should not fail due to expiration
        assert_not result.errors[:tags]&.any? { |e| e.include?("expired") }
      end

      test "accepts events without expiration tag" do
        event_data = valid_event(tags: [ [ "p", SecureRandom.hex(32) ] ])

        result = EventContract.new.call(event_data)

        # Should not fail due to expiration
        assert_not result.errors[:tags]&.any? { |e| e.include?("expired") }
      end

      test "ignores invalid expiration timestamp (zero)" do
        event_data = valid_event(tags: [ [ "expiration", "0" ] ])

        result = EventContract.new.call(event_data)

        # Should not fail due to expiration (zero is ignored)
        assert_not result.errors[:tags]&.any? { |e| e.include?("expired") }
      end

      test "ignores invalid expiration timestamp (non-numeric)" do
        event_data = valid_event(tags: [ [ "expiration", "invalid" ] ])

        result = EventContract.new.call(event_data)

        # Should not fail due to expiration (non-numeric parses to 0)
        assert_not result.errors[:tags]&.any? { |e| e.include?("expired") }
      end

      # =========================================================================
      # Basic Validation
      # =========================================================================

      test "validates valid event" do
        result = EventContract.new.call(valid_event)

        assert result.success?, "Expected success but got: #{result.errors.to_h}"
      end

      test "rejects invalid event_id (not 64 hex chars)" do
        event_data = valid_event(id: "short")

        result = EventContract.new.call(event_data)

        assert result.failure?
        assert result.errors[:id].present?
      end

      test "rejects invalid pubkey" do
        event_data = valid_event(pubkey: "invalid")

        result = EventContract.new.call(event_data)

        assert result.failure?
        assert result.errors[:pubkey].present?
      end

      test "rejects invalid sig (not 128 hex chars)" do
        event_data = valid_event(sig: "short")

        result = EventContract.new.call(event_data)

        assert result.failure?
        assert result.errors[:sig].present?
      end

      test "rejects future created_at beyond grace period" do
        future_time = Time.now.to_i + 1800  # 30 min in future (beyond 15 min grace)
        event_data = valid_event(created_at: future_time)

        result = EventContract.new.call(event_data)

        assert result.failure?
        assert result.errors[:created_at].present?
      end

      test "accepts created_at within grace period" do
        grace_time = Time.now.to_i + 600  # 10 min in future (within 15 min grace)
        event_data = valid_event(created_at: grace_time)

        result = EventContract.new.call(event_data)

        assert_not result.errors[:created_at]&.present?
      end

      test "rejects kind outside valid range" do
        event_data = valid_event(kind: 70_000)

        result = EventContract.new.call(event_data)

        assert result.failure?
        assert result.errors[:kind].present?
      end
    end
  end
end
