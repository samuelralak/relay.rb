# frozen_string_literal: true

require "test_helper"

module Sync
  class RecoverStaleTest < ActiveSupport::TestCase
    setup do
      @stale_threshold = 5.minutes
      @error_retry_after = 30.minutes
    end

    # =========================================================================
    # Stale Sync Recovery
    # =========================================================================

    test "recovers syncing states that exceed stale threshold" do
      stale_sync = create_sync_state(
        relay_url: "wss://stale.relay.com",
        status: "syncing",
        updated_at: 10.minutes.ago
      )

      result = RecoverStale.call(stale_threshold: @stale_threshold.to_i)

      stale_sync.reload
      assert_equal "idle", stale_sync.status
      assert_equal 1, result.value![:recovered_stale]
    end

    test "does not recover recently updated syncing states" do
      recent_sync = create_sync_state(
        relay_url: "wss://recent.relay.com",
        status: "syncing",
        updated_at: 1.minute.ago
      )

      result = RecoverStale.call(stale_threshold: @stale_threshold.to_i)

      recent_sync.reload
      assert_equal "syncing", recent_sync.status
      assert_equal 0, result.value![:recovered_stale]
    end

    test "only recovers syncing states, not other statuses" do
      idle = create_sync_state(relay_url: "wss://idle.relay.com", status: "idle", updated_at: 1.hour.ago)
      completed = create_sync_state(relay_url: "wss://completed.relay.com", status: "completed", updated_at: 1.hour.ago)

      result = RecoverStale.call(stale_threshold: @stale_threshold.to_i)

      idle.reload
      completed.reload
      assert_equal "idle", idle.status
      assert_equal "completed", completed.status
      assert_equal 0, result.value![:recovered_stale]
    end

    test "recovers multiple stale syncs" do
      3.times do |i|
        create_sync_state(
          relay_url: "wss://stale#{i}.relay.com",
          status: "syncing",
          updated_at: 15.minutes.ago
        )
      end

      result = RecoverStale.call(stale_threshold: @stale_threshold.to_i)

      assert_equal 3, result.value![:recovered_stale]
      assert_equal 0, SyncState.syncing.count
    end

    # =========================================================================
    # Error Retry
    # =========================================================================

    test "retries errored states after retry period" do
      old_error = create_sync_state(
        relay_url: "wss://error.relay.com",
        status: "error",
        error_message: "Connection timeout",
        updated_at: 1.hour.ago
      )

      result = RecoverStale.call(error_retry_after: @error_retry_after.to_i)

      old_error.reload
      assert_equal "idle", old_error.status
      assert_nil old_error.error_message
      assert_equal 1, result.value![:retried_errors]
    end

    test "does not retry recent errors" do
      recent_error = create_sync_state(
        relay_url: "wss://recent-error.relay.com",
        status: "error",
        error_message: "Connection refused",
        updated_at: 5.minutes.ago
      )

      result = RecoverStale.call(error_retry_after: @error_retry_after.to_i)

      recent_error.reload
      assert_equal "error", recent_error.status
      assert_equal "Connection refused", recent_error.error_message
      assert_equal 0, result.value![:retried_errors]
    end

    # =========================================================================
    # Combined Recovery
    # =========================================================================

    test "recovers both stale and errored states in single call" do
      stale = create_sync_state(
        relay_url: "wss://stale.relay.com",
        status: "syncing",
        updated_at: 10.minutes.ago
      )
      errored = create_sync_state(
        relay_url: "wss://error.relay.com",
        status: "error",
        updated_at: 1.hour.ago
      )

      result = RecoverStale.call(
        stale_threshold: @stale_threshold.to_i,
        error_retry_after: @error_retry_after.to_i
      )

      assert_equal 1, result.value![:recovered_stale]
      assert_equal 1, result.value![:retried_errors]

      stale.reload
      errored.reload
      assert_equal "idle", stale.status
      assert_equal "idle", errored.status
    end

    test "returns zero counts when nothing to recover" do
      # Only healthy states
      create_sync_state(relay_url: "wss://healthy.relay.com", status: "idle")

      result = RecoverStale.call(
        stale_threshold: @stale_threshold.to_i,
        error_retry_after: @error_retry_after.to_i
      )

      assert_equal 0, result.value![:recovered_stale]
      assert_equal 0, result.value![:retried_errors]
    end

    private

    def create_sync_state(attrs)
      defaults = {
        direction: "down",
        filter_hash: SecureRandom.hex(8),
        events_downloaded: 0,
        events_uploaded: 0
      }
      SyncState.create!(defaults.merge(attrs))
    end
  end
end
