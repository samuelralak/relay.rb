# frozen_string_literal: true

require "test_helper"

module Events
  class ProcessJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    # =========================================================================
    # Queue Configuration
    # =========================================================================

    test "job is enqueued to events queue" do
      assert_equal "events", Events::ProcessJob.new.queue_name
    end

    # =========================================================================
    # Successful Processing
    # =========================================================================

    test "processes valid event JSON" do
      event_data = {
        id: SecureRandom.hex(32),
        pubkey: SecureRandom.hex(32),
        created_at: Time.current.to_i,
        kind: 1,
        tags: [],
        content: "Test event",
        sig: SecureRandom.hex(64)
      }

      assert_difference "Event.count", 1 do
        Events::ProcessJob.new.perform(event_data.to_json, "wss://relay.example.com")
      end
    end

    test "processes event without source_relay" do
      event_data = {
        id: SecureRandom.hex(32),
        pubkey: SecureRandom.hex(32),
        created_at: Time.current.to_i,
        kind: 1,
        tags: [],
        content: "No source relay",
        sig: SecureRandom.hex(64)
      }

      assert_difference "Event.count", 1 do
        Events::ProcessJob.new.perform(event_data.to_json)
      end
    end

    # =========================================================================
    # Error Handling
    # =========================================================================

    test "handles invalid JSON gracefully" do
      assert_nothing_raised do
        Events::ProcessJob.new.perform("not valid json {{{")
      end
    end

    test "does not create event for invalid JSON" do
      assert_no_difference "Event.count" do
        Events::ProcessJob.new.perform("invalid json")
      end
    end

    test "handles duplicate events gracefully" do
      event_data = {
        id: SecureRandom.hex(32),
        pubkey: SecureRandom.hex(32),
        created_at: Time.current.to_i,
        kind: 1,
        tags: [],
        content: "Duplicate test",
        sig: SecureRandom.hex(64)
      }

      # First call succeeds
      Events::ProcessJob.new.perform(event_data.to_json)

      # Second call with same event doesn't raise
      assert_nothing_raised do
        assert_no_difference "Event.count" do
          Events::ProcessJob.new.perform(event_data.to_json)
        end
      end
    end

    # =========================================================================
    # Job Enqueueing
    # =========================================================================

    test "can be enqueued with perform_later" do
      event_data = { id: "abc123", kind: 1 }

      assert_enqueued_with(job: Events::ProcessJob, queue: "events") do
        Events::ProcessJob.perform_later(event_data.to_json, "wss://test.relay.com")
      end
    end
  end
end
