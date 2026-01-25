# frozen_string_literal: true

require "test_helper"

module Events
  module Actions
    class HandleDeletionTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      # =========================================================================
      # Test Data
      # =========================================================================

      def valid_deletion_event(overrides = {})
        {
          "id" => overrides[:id] || SecureRandom.hex(32),
          "pubkey" => overrides[:pubkey] || "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "created_at" => overrides[:created_at] || Time.current.to_i,
          "kind" => 5,
          "tags" => overrides[:tags] || [],
          "content" => overrides[:content] || "deleted",
          "sig" => SecureRandom.hex(64)
        }
      end

      # =========================================================================
      # Successful Processing
      # =========================================================================

      test "stores deletion event" do
        event_data = valid_deletion_event

        assert_difference "Event.count", 1 do
          result = HandleDeletion.call(event_data:)

          assert result.success?
        end

        event = Event.find_by(event_id: event_data["id"])
        assert_not_nil event
        assert_equal 5, event.kind
      end

      test "enqueues ProcessDeletionJob" do
        event_data = valid_deletion_event(
          tags: [["e", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]
        )

        assert_enqueued_with(job: ProcessDeletionJob, queue: "deletions") do
          HandleDeletion.call(event_data:)
        end
      end

      test "enqueues job with event id" do
        event_data = valid_deletion_event

        result = HandleDeletion.call(event_data:)

        assert result.success?
        stored_event = result.value!

        assert_enqueued_jobs 1, only: ProcessDeletionJob
        enqueued_job = enqueued_jobs.find { |job| job["job_class"] == "Events::ProcessDeletionJob" }
        assert_equal [stored_event.id], enqueued_job["arguments"]
      end

      # =========================================================================
      # Duplicate Handling
      # =========================================================================

      test "does not enqueue job for duplicate" do
        # Use a fixed event_id for both calls
        fixed_id = SecureRandom.hex(32)
        event_data = valid_deletion_event(id: fixed_id)

        # First call stores and enqueues
        HandleDeletion.call(event_data:)
        clear_enqueued_jobs

        # Second call with SAME event data should not enqueue
        assert_no_enqueued_jobs only: ProcessDeletionJob do
          result = HandleDeletion.call(event_data:)

          assert result.success?
          assert result.value![:duplicate]
        end
      end

      test "returns duplicate marker for existing deletion event" do
        # Use a fixed event_id for both calls
        fixed_id = SecureRandom.hex(32)
        event_data = valid_deletion_event(id: fixed_id)

        HandleDeletion.call(event_data:)

        result = HandleDeletion.call(event_data:)

        assert result.success?
        assert result.value![:duplicate]
        assert_equal event_data["id"], result.value![:event_id]
      end

      # =========================================================================
      # Return Values
      # =========================================================================

      test "returns stored event on success" do
        event_data = valid_deletion_event

        result = HandleDeletion.call(event_data:)

        assert result.success?
        assert_kind_of Event, result.value!
        assert_equal event_data["id"], result.value!.event_id
      end
    end
  end
end
