# frozen_string_literal: true

require "test_helper"

class PollingSyncJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SyncState.delete_all
    @relay_url = "wss://test.relay.com"
  end

  # =========================================================================
  # Queue Configuration
  # =========================================================================

  test "job is enqueued to sync queue" do
    assert_equal "sync", PollingSyncJob.new.queue_name
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
    # Verify by checking no ProcessEventJob is enqueued
    assert_no_enqueued_jobs only: ProcessEventJob do
      # Need to capture that job returns early
      # Since we can't connect, we verify via sync state
      job = PollingSyncJob.new
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
      PollingSyncJob.new.perform(relay_url: @relay_url, filter: {}, mode: "realtime")
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
      PollingSyncJob.new.perform(relay_url: @relay_url, filter: {}, mode: "realtime")
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
      PollingSyncJob.new.perform(relay_url: @relay_url, filter: {}, mode: "realtime")
    end

    state.reload
    assert_equal "error", state.status
    assert state.error_message.present?
  end

  # =========================================================================
  # Job Enqueueing
  # =========================================================================

  test "can be enqueued with perform_later" do
    assert_enqueued_with(job: PollingSyncJob, queue: "sync") do
      PollingSyncJob.perform_later(
        relay_url: @relay_url,
        filter: { kinds: [ 1 ] },
        mode: "realtime"
      )
    end
  end

  test "enqueued job preserves arguments" do
    PollingSyncJob.perform_later(
      relay_url: @relay_url,
      filter: { kinds: [ 1 ], since: 12345 },
      mode: "backfill"
    )

    enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "PollingSyncJob" }
    assert_not_nil enqueued_job
    args = enqueued_job["arguments"].first
    assert_equal @relay_url, args["relay_url"]
    assert_equal "backfill", args["mode"]
    # Filter keys are preserved (ActiveJob adds _aj_symbol_keys for serialization)
    assert_equal [ 1 ], args["filter"]["kinds"]
    assert_equal 12345, args["filter"]["since"]
  end
end
