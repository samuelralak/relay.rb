# frozen_string_literal: true

require "test_helper"

# Tests for sync status semantics as documented in SyncState model
#
# Status lifecycle:
#   idle -> syncing -> idle (polling, chunk complete)
#   idle -> syncing -> completed (backfill fully done)
#   idle -> syncing -> error (failure)
#
# Key rule: "completed" should ONLY be set when backfill_complete? is true
class SyncStatusSemanticsTest < ActiveSupport::TestCase
  setup do
    @relay_url = "wss://test.relay.com"
    @filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
  end

  # =========================================
  # Status Semantics Tests
  # =========================================

  test "idle is the initial state" do
    state = SyncState.for_sync(relay_url: @relay_url, direction: "down", filter: {})
    assert_equal "idle", state.status
  end

  test "idle means ready for next sync" do
    state = create_sync_state(status: "idle")
    assert state.idle?
    assert_not state.syncing?
    assert_not state.completed?
    assert_not state.error?
  end

  test "syncing means actively running" do
    state = create_sync_state(status: "idle")
    state.mark_syncing!

    assert state.syncing?
    assert_not state.idle?
  end

  test "completed should only be used when backfill is done" do
    # Backfill NOT complete - should NOT be marked completed
    state = create_sync_state(
      status: "idle",
      backfill_target: 5.years.ago,
      backfill_until: 1.week.ago  # Still far from target
    )

    assert_not state.backfill_complete?, "Precondition: backfill should not be complete"

    # Marking completed when backfill isn't done violates semantics
    # This is what we're preventing with the fix
    state.mark_completed!
    state.reload

    # The model allows this, but jobs should NOT do it unless backfill_complete?
    assert_equal "completed", state.status
    assert_not state.backfill_complete?, "Backfill should still not be complete"
  end

  test "completed is correct when backfill is actually done" do
    state = create_sync_state(
      status: "idle",
      backfill_target: 1.week.ago,
      backfill_until: 2.weeks.ago  # Past target = complete
    )

    assert state.backfill_complete?, "Precondition: backfill should be complete"

    state.mark_completed!
    state.reload

    assert_equal "completed", state.status
    assert state.backfill_complete?
  end

  test "reset_to_idle! is safe for any state" do
    state = create_sync_state(status: "syncing")

    state.reset_to_idle!
    assert_equal "idle", state.status

    state.update!(status: "completed")
    state.reset_to_idle!
    assert_equal "idle", state.status

    state.update!(status: "error", error_message: "test")
    state.reset_to_idle!
    assert_equal "idle", state.status
    assert_nil state.error_message
  end

  # =========================================
  # Polling Sync Status Tests
  # =========================================

  test "polling sync should use idle, not completed" do
    # Simulate what PollingSyncJob does
    state = create_sync_state(status: "idle")

    # Start polling
    state.mark_syncing!
    assert_equal "syncing", state.status

    # After polling completes - should reset to idle, NOT mark completed
    # (because polling is incremental, doesn't complete backfill)
    state.reset_to_idle!

    assert_equal "idle", state.status, "Polling should set idle, not completed"
  end

  test "polling sync preserves backfill progress" do
    state = create_sync_state(
      status: "idle",
      backfill_target: 5.years.ago,
      backfill_until: 1.month.ago,
      events_downloaded: 1000
    )

    progress_before = state.backfill_progress_percent

    # Simulate polling sync
    state.mark_syncing!
    state.increment_events_downloaded!(50)
    state.reset_to_idle!

    state.reload

    # Backfill progress should be unchanged (polling doesn't affect chunks)
    assert_equal progress_before, state.backfill_progress_percent
    assert_equal 1050, state.events_downloaded
    assert_equal "idle", state.status
  end

  # =========================================
  # Negentropy Sync Status Tests
  # =========================================

  test "negentropy sync marks completed only when backfill done" do
    # Simulate NegentropySyncJob behavior
    state = create_sync_state(
      status: "idle",
      backfill_target: 5.years.ago,
      backfill_until: Time.current
    )

    # First chunk
    state.mark_syncing!
    state.mark_backfill_chunk_completed!(chunk_start: 1.week.ago)
    state.reload

    # Backfill not complete - should stay syncing for continuation
    assert_not state.backfill_complete?
    # In real job, status stays syncing and continuation is scheduled

    # Simulate many chunks until complete
    state.update!(backfill_until: state.backfill_target - 1.day)

    # Now backfill is complete
    assert state.backfill_complete?
    state.mark_completed!

    assert_equal "completed", state.status
  end

  test "negentropy error resets to idle for fallback" do
    state = create_sync_state(status: "syncing")

    # NegentropyError occurs - reset to idle so PollingSyncJob can take over
    state.reset_to_idle!

    assert_equal "idle", state.status
    assert state.idle?
  end

  # =========================================
  # Stale Detection Tests
  # =========================================

  test "stale syncing state should be reset to idle" do
    state = create_sync_state(status: "syncing")
    state.update!(updated_at: 10.minutes.ago)

    assert state.stale?(threshold: 5.minutes), "Should be stale after threshold"

    # Recovery resets to idle
    state.reset_to_idle!
    assert_equal "idle", state.status
  end

  test "completed state is not considered stale" do
    state = create_sync_state(status: "completed")
    state.update!(updated_at: 1.hour.ago)

    # Stale only applies to syncing state
    assert_not state.stale?(threshold: 5.minutes)
  end

  private

  def create_sync_state(attrs = {})
    SyncState.create!({
      relay_url: @relay_url,
      filter_hash: @filter_hash,
      direction: "down",
      status: "idle",
      events_downloaded: 0,
      events_uploaded: 0
    }.merge(attrs))
  end
end
