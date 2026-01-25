# frozen_string_literal: true

require "test_helper"

# Integration tests for the sync orchestration system
# Tests multi-component flows that span jobs, services, and state management
#
# Note: Unit tests for individual components exist in:
# - test/services/sync/orchestrator_test.rb (dispatch logic)
# - test/services/sync/recover_stale_test.rb (recovery logic)
# - test/jobs/ (individual job behavior)
class SyncOrchestrationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SyncState.delete_all
    @original_config = RelaySync.instance_variable_get(:@configuration)
  end

  teardown do
    RelaySync.instance_variable_set(:@configuration, @original_config)
  end

  def create_fake_relay(url:, negentropy: false, backfill: false, direction: "down")
    relay = Object.new
    relay.define_singleton_method(:url) do url end
    relay.define_singleton_method(:negentropy?) do negentropy end
    relay.define_singleton_method(:backfill?) do backfill end
    relay.define_singleton_method(:direction) do direction end
    relay.define_singleton_method(:enabled?) do true end
    relay.define_singleton_method(:upload_enabled?) do direction == "up" || direction == "both" end
    relay
  end

  def with_relays(backfill: [], download: [], upload: [])
    fake_config = Object.new
    fake_config.define_singleton_method(:backfill_relays) do backfill end
    fake_config.define_singleton_method(:download_relays) do download end
    fake_config.define_singleton_method(:upload_relays) do upload end
    fake_config.define_singleton_method(:find_relay) do |url| (backfill + download + upload).find { |r| r.url == url } end
    fake_config.define_singleton_method(:sync_settings) do @original_config&.sync_settings || RelaySync::Configuration.new.sync_settings end

    RelaySync.instance_variable_set(:@configuration, fake_config)
    yield
  end

  # =========================================================================
  # Recovery -> Orchestration Flow
  # Tests that recovery jobs reset state so orchestration can re-dispatch
  # =========================================================================

  test "stale sync recovery enables re-orchestration" do
    relay = create_fake_relay(url: "wss://stuck.relay.com", negentropy: true, backfill: true)

    filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
    sync_state = SyncState.create!(
      relay_url: relay.url,
      filter_hash:,
      direction: "down",
      status: "syncing",
      updated_at: 1.minute.ago, # Recent - not stale yet
      events_downloaded: 50,
      events_uploaded: 0
    )

    # Active syncing state: orchestration skips
    with_relays(backfill: [ relay ]) do
      Sync::OrchestratorJob.new.perform(mode: "backfill")
      assert_empty enqueued_jobs, "Should skip actively syncing relay"
    end

    # State becomes stale
    sync_state.update!(updated_at: 30.minutes.ago)

    # Recovery resets stale state
    Sync::RecoveryJob.new.perform
    sync_state.reload
    assert_equal "idle", sync_state.status

    # Now orchestration dispatches
    with_relays(backfill: [ relay ]) do
      Sync::OrchestratorJob.new.perform(mode: "backfill")
      assert_equal 1, enqueued_jobs.size, "Should dispatch after recovery"
    end
  end

  test "error recovery clears state for retry" do
    relay = create_fake_relay(url: "wss://errored.relay.com", negentropy: false, backfill: true)

    # Sync failed with error
    filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
    errored_state = SyncState.create!(
      relay_url: relay.url,
      filter_hash:,
      direction: "down",
      status: "error",
      error_message: "Connection failed",
      updated_at: 1.hour.ago,
      events_downloaded: 0,
      events_uploaded: 0
    )

    # Recovery clears error
    Sync::RecoveryJob.new.perform

    errored_state.reload
    assert_equal "idle", errored_state.status
    assert_nil errored_state.error_message

    # Orchestration can now dispatch
    with_relays(backfill: [ relay ]) do
      Sync::OrchestratorJob.new.perform(mode: "backfill")
      assert_equal 1, enqueued_jobs.size
    end
  end

  # =========================================================================
  # Status Lifecycle
  # Tests the full status lifecycle as components interact
  # =========================================================================

  test "polling sync lifecycle: idle -> syncing -> idle with progress preserved" do
    state = SyncState.create!(
      relay_url: "wss://lifecycle.relay.com",
      filter_hash: SyncState.compute_filter_hash(direction: "down", filter: {}),
      direction: "down",
      status: "idle",
      events_downloaded: 0,
      events_uploaded: 0
    )

    # Start sync
    state.mark_syncing!
    assert_equal "syncing", state.status

    # Record progress
    state.mark_download_progress!(event_id: "abc123", timestamp: Time.current, count: 10)
    assert_equal 10, state.events_downloaded

    # Complete polling (returns to idle, not completed)
    state.reset_to_idle!
    assert_equal "idle", state.status
    assert_equal 10, state.events_downloaded
    assert state.resumable?
  end

  test "backfill lifecycle: marks completed only when backfill_complete?" do
    state = SyncState.create!(
      relay_url: "wss://backfill.relay.com",
      filter_hash: SyncState.compute_filter_hash(direction: "down", filter: {}),
      direction: "down",
      status: "idle",
      backfill_target: 1.week.ago,
      backfill_until: Time.current,
      events_downloaded: 0,
      events_uploaded: 0
    )

    assert_not state.backfill_complete?

    # Process chunk that completes backfill
    state.mark_syncing!
    state.mark_backfill_chunk_completed!(chunk_start: 2.weeks.ago)

    assert state.backfill_complete?
    state.mark_completed!
    assert_equal "completed", state.status
  end

  # =========================================================================
  # Polling Backfill Lifecycle
  # =========================================================================

  test "polling backfill lifecycle: initializes, chunks forward, completes" do
    relay = create_fake_relay(url: "wss://polling-backfill.relay.com", negentropy: false, backfill: true)

    with_relays(backfill: [ relay ]) do
      # First dispatch
      Sync::OrchestratorJob.new.perform(mode: "backfill")

      job = enqueued_jobs.find { |j| j["job_class"] == "Sync::PollingJob" }
      assert_not_nil job
      args = job["arguments"].first
      assert args["backfill_target"].present?
    end

    # Simulate state after completion
    filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
    state = SyncState.find_or_create_by!(relay_url: relay.url, filter_hash:) { |s|
      s.direction = "down"
      s.events_downloaded = 0
      s.events_uploaded = 0
    }
    state.update!(
      status: "completed",
      backfill_target: 1.month.ago,
      backfill_until: 30.minutes.ago
    )

    clear_enqueued_jobs

    # Orchestration should skip completed relay
    with_relays(backfill: [ relay ]) do
      Sync::OrchestratorJob.new.perform(mode: "backfill")
      assert_empty enqueued_jobs, "Should skip completed polling backfill"
    end
  end
end
