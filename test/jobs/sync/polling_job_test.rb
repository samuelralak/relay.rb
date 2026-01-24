# frozen_string_literal: true

require "test_helper"

module Sync
  class PollingJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      SyncState.delete_all
      @relay_url = "wss://test.relay.com"
    end

    # =========================================================================
    # Queue Configuration
    # =========================================================================

    test "job is enqueued to sync queue" do
      assert_equal "sync", Sync::PollingJob.new.queue_name
    end

    # =========================================================================
    # Skip Already Syncing
    # =========================================================================

    test "skips when already syncing and not stale" do
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      SyncState.create!(
        relay_url: @relay_url,
        filter_hash:,
        direction: "down",
        status: "syncing",
        updated_at: 1.minute.ago, # Recent, not stale
        events_downloaded: 0,
        events_uploaded: 0
      )

      # Should return early without attempting connection
      # Verify by checking no Events::ProcessJob is enqueued
      assert_no_enqueued_jobs only: Events::ProcessJob do
        # Need to capture that job returns early
        # Since we can't connect, we verify via sync state
        job = Sync::PollingJob.new
        job.perform(relay_url: @relay_url, filter: {}, mode: "realtime")
      end

      # State should remain syncing (unchanged)
      state = SyncState.find_by(relay_url: @relay_url)
      assert_equal "syncing", state.status
    end

    # =========================================================================
    # Stale State Reset
    # =========================================================================

    test "resets stale syncing state before processing" do
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      stale_state = SyncState.create!(
        relay_url: @relay_url,
        filter_hash:,
        direction: "down",
        status: "syncing",
        updated_at: 1.hour.ago, # Stale
        events_downloaded: 0,
        events_uploaded: 0
      )

      # Job will try to connect and fail, but should reset stale state first
      # We expect ConnectionError because there's no real relay
      assert_raises(RelaySync::ConnectionError) do
        Sync::PollingJob.new.perform(relay_url: @relay_url, filter: {}, mode: "realtime")
      end

      # After error, state should be marked as error (not stuck in syncing)
      stale_state.reload
      assert_equal "error", stale_state.status
    end

    # =========================================================================
    # SyncState Creation
    # =========================================================================

    test "creates sync state if not exists" do
      assert_equal 0, SyncState.count

      # Will fail on connection but should create state
      assert_raises(RelaySync::ConnectionError) do
        Sync::PollingJob.new.perform(relay_url: @relay_url, filter: {}, mode: "realtime")
      end

      assert_equal 1, SyncState.count
      state = SyncState.first
      assert_equal @relay_url, state.relay_url
      assert_equal "down", state.direction
    end

    # =========================================================================
    # Status Management
    # =========================================================================

    test "marks error on exception" do
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      state = SyncState.create!(
        relay_url: @relay_url,
        filter_hash:,
        direction: "down",
        status: "idle",
        events_downloaded: 0,
        events_uploaded: 0
      )

      assert_raises(RelaySync::ConnectionError) do
        Sync::PollingJob.new.perform(relay_url: @relay_url, filter: {}, mode: "realtime")
      end

      state.reload
      assert_equal "error", state.status
      assert state.error_message.present?
    end

    # =========================================================================
    # Job Enqueueing
    # =========================================================================

    test "can be enqueued with perform_later" do
      assert_enqueued_with(job: Sync::PollingJob, queue: "sync") do
        Sync::PollingJob.perform_later(
          relay_url: @relay_url,
          filter: { kinds: [ 1 ] },
          mode: "realtime"
        )
      end
    end

    test "enqueued job preserves arguments" do
      Sync::PollingJob.perform_later(
        relay_url: @relay_url,
        filter: { kinds: [ 1 ], since: 12345 },
        mode: "backfill"
      )

      enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::PollingJob" }
      assert_not_nil enqueued_job
      args = enqueued_job["arguments"].first
      assert_equal @relay_url, args["relay_url"]
      assert_equal "backfill", args["mode"]
      # Filter keys are preserved (ActiveJob adds _aj_symbol_keys for serialization)
      assert_equal [ 1 ], args["filter"]["kinds"]
      assert_equal 12345, args["filter"]["since"]
    end

    # =========================================================================
    # Chunked Backfill Mode
    # =========================================================================

    test "backfill mode initializes polling backfill tracking" do
      # Will fail on connection but should initialize tracking
      assert_raises(RelaySync::ConnectionError) do
        Sync::PollingJob.new.perform(
          relay_url: @relay_url,
          filter: {},
          mode: "backfill",
          backfill_target: 1.month.ago.to_i,
          chunk_hours: 168
        )
      end

      state = SyncState.find_by(relay_url: @relay_url)
      assert state.backfill_target.present?
      assert state.backfill_until.present?
    end

    test "backfill mode marks completed when polling backfill is done" do
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      state = SyncState.create!(
        relay_url: @relay_url,
        filter_hash:,
        direction: "down",
        status: "idle",
        backfill_target: 1.month.ago,
        backfill_until: 30.minutes.ago, # Already caught up
        events_downloaded: 100,
        events_uploaded: 0
      )

      job = Sync::PollingJob.new
      job.perform(
        relay_url: @relay_url,
        filter: {},
        mode: "backfill",
        backfill_target: 1.month.ago.to_i,
        chunk_hours: 168
      )

      state.reload
      assert_equal "completed", state.status
    end

    test "backfill continuation job bypasses syncing check" do
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      state = SyncState.create!(
        relay_url: @relay_url,
        filter_hash:,
        direction: "down",
        status: "syncing",
        updated_at: 1.minute.ago, # Recent, not stale
        backfill_target: 1.month.ago,
        backfill_until: 30.minutes.ago, # Already caught up
        events_downloaded: 100,
        events_uploaded: 0
      )

      # Regular job would skip, continuation should proceed
      job = Sync::PollingJob.new
      job.perform(
        relay_url: @relay_url,
        filter: {},
        mode: "backfill",
        backfill_target: 1.month.ago.to_i,
        chunk_hours: 168,
        continuation: true
      )

      state.reload
      assert_equal "completed", state.status
    end

    test "enqueued backfill job preserves chunking arguments" do
      Sync::PollingJob.perform_later(
        relay_url: @relay_url,
        filter: {},
        mode: "backfill",
        backfill_target: 1.month.ago.to_i,
        chunk_hours: 24
      )

      enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::PollingJob" }
      args = enqueued_job["arguments"].first
      assert_equal "backfill", args["mode"]
      assert args["backfill_target"].present?
      assert_equal 24, args["chunk_hours"]
    end

    test "realtime mode without backfill_target uses original behavior" do
      # Will fail on connection but should use realtime path
      assert_raises(RelaySync::ConnectionError) do
        Sync::PollingJob.new.perform(
          relay_url: @relay_url,
          filter: { since: 1.hour.ago.to_i },
          mode: "realtime"
        )
      end

      state = SyncState.find_by(relay_url: @relay_url)
      # Realtime mode doesn't initialize backfill tracking
      assert_nil state.backfill_target
    end

    # =========================================================================
    # Regression Tests - Existing Behavior Preserved
    # =========================================================================

    test "regression: mode parameter defaults to realtime" do
      Sync::PollingJob.perform_later(relay_url: @relay_url, filter: {})

      enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::PollingJob" }
      args = enqueued_job["arguments"].first
      # mode defaults to REALTIME, backfill_target not present
      assert_equal "realtime", args.fetch("mode", "realtime")
      assert_nil args["backfill_target"]
    end

    test "regression: filter with since works in realtime mode" do
      # Existing behavior: filter[:since] is used as fallback_since in resume_filter
      Sync::PollingJob.perform_later(
        relay_url: @relay_url,
        filter: { since: 1.hour.ago.to_i },
        mode: "realtime"
      )

      enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::PollingJob" }
      args = enqueued_job["arguments"].first
      assert_equal 1.hour.ago.to_i, args["filter"]["since"]
      assert_nil args["backfill_target"]  # Not backfill mode
    end

    test "regression: backfill mode without backfill_target uses realtime path" do
      # Edge case: mode is "backfill" but backfill_target is nil
      # Should fall through to realtime behavior (backfill_mode? returns false)
      Sync::PollingJob.perform_later(
        relay_url: @relay_url,
        filter: {},
        mode: "backfill"
        # Note: no backfill_target provided
      )

      enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::PollingJob" }
      args = enqueued_job["arguments"].first
      assert_equal "backfill", args["mode"]
      assert_nil args["backfill_target"]  # Will use realtime path
    end
  end
end
