# frozen_string_literal: true

require "test_helper"

module Sync
  class RecoveryJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      SyncState.delete_all
    end

    # =========================================================================
    # Queue Configuration
    # =========================================================================

    test "job is enqueued to sync queue" do
      assert_equal "sync", Sync::RecoveryJob.new.queue_name
    end

    # =========================================================================
    # Recovery Execution
    # =========================================================================

    test "executes without error when no stale states exist" do
      assert_nothing_raised do
        Sync::RecoveryJob.new.perform
      end
    end

    test "recovers stale syncing states" do
      stale_state = SyncState.create!(
        relay_url: "wss://stale.relay.com",
        filter_hash: SecureRandom.hex(8),
        direction: "down",
        status: "syncing",
        updated_at: 15.minutes.ago,
        events_downloaded: 0,
        events_uploaded: 0
      )

      Sync::RecoveryJob.new.perform

      stale_state.reload
      assert_equal "idle", stale_state.status
    end

    test "retries errored states after retry period" do
      errored_state = SyncState.create!(
        relay_url: "wss://error.relay.com",
        filter_hash: SecureRandom.hex(8),
        direction: "down",
        status: "error",
        error_message: "Connection failed",
        updated_at: 1.hour.ago,
        events_downloaded: 0,
        events_uploaded: 0
      )

      Sync::RecoveryJob.new.perform

      errored_state.reload
      assert_equal "idle", errored_state.status
      assert_nil errored_state.error_message
    end

    test "does not affect healthy idle states" do
      idle_state = SyncState.create!(
        relay_url: "wss://healthy.relay.com",
        filter_hash: SecureRandom.hex(8),
        direction: "down",
        status: "idle",
        events_downloaded: 100,
        events_uploaded: 0
      )

      Sync::RecoveryJob.new.perform

      idle_state.reload
      assert_equal "idle", idle_state.status
      assert_equal 100, idle_state.events_downloaded
    end

    # =========================================================================
    # Job Enqueueing
    # =========================================================================

    test "can be enqueued with perform_later" do
      assert_enqueued_with(job: Sync::RecoveryJob, queue: "sync") do
        Sync::RecoveryJob.perform_later
      end
    end
  end
end
