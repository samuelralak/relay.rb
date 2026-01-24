# frozen_string_literal: true

require "test_helper"

module Sync
  class DispatchSyncJobsTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    # =========================================================================
    # Test Helpers
    # =========================================================================

    setup do
      # Clear any existing sync states
      SyncState.delete_all

      # Store original configuration
      @original_config = RelaySync.instance_variable_get(:@configuration)

      # Create fake relay configurations
      @negentropy_relay = create_fake_relay(
        url: "wss://negentropy.relay.com",
        negentropy: true,
        backfill: true,
        direction: "down"
      )
      @polling_relay = create_fake_relay(
        url: "wss://polling.relay.com",
        negentropy: false,
        backfill: true,
        direction: "down"
      )
      @upload_relay = create_fake_relay(
        url: "wss://upload.relay.com",
        negentropy: false,
        backfill: false,
        direction: "up"
      )
    end

    teardown do
      # Restore original configuration
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

    def with_fake_configuration(backfill: [], download: [], upload: [])
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
    # Backfill Mode
    # =========================================================================

    test "backfill mode dispatches Sync::NegentropyJob for negentropy-capable relays" do
      with_fake_configuration(backfill: [ @negentropy_relay ]) do
        assert_enqueued_with(job: Sync::NegentropyJob) do
          result = DispatchSyncJobs.call(mode: "backfill")
          assert_equal 1, result.value![:dispatched]
        end
      end
    end

    test "backfill mode dispatches Sync::PollingJob for non-negentropy relays" do
      with_fake_configuration(backfill: [ @polling_relay ]) do
        assert_enqueued_with(job: Sync::PollingJob) do
          result = DispatchSyncJobs.call(mode: "backfill")
          assert_equal 1, result.value![:dispatched]
        end
      end
    end

    test "backfill mode job has correct relay_url" do
      with_fake_configuration(backfill: [ @negentropy_relay ]) do
        DispatchSyncJobs.call(mode: "backfill")

        enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::NegentropyJob" }
        assert_not_nil enqueued_job
        args = enqueued_job["arguments"].first
        assert_equal "wss://negentropy.relay.com", args["relay_url"]
      end
    end

    # =========================================================================
    # Realtime Mode
    # =========================================================================

    test "realtime mode dispatches Sync::PollingJob" do
      with_fake_configuration(download: [ @polling_relay ]) do
        assert_enqueued_with(job: Sync::PollingJob) do
          result = DispatchSyncJobs.call(mode: "realtime")
          assert_equal 1, result.value![:dispatched]
        end
      end
    end

    test "realtime mode job has realtime mode and since filter" do
      with_fake_configuration(download: [ @polling_relay ]) do
        DispatchSyncJobs.call(mode: "realtime")

        enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::PollingJob" }
        assert_not_nil enqueued_job
        args = enqueued_job["arguments"].first
        assert_equal "realtime", args["mode"]
        assert args["filter"]["since"].present?
      end
    end

    # =========================================================================
    # Upload Mode
    # =========================================================================

    test "upload mode dispatches Sync::UploadJob for upload relays" do
      with_fake_configuration(upload: [ @upload_relay ]) do
        assert_enqueued_with(job: Sync::UploadJob) do
          result = DispatchSyncJobs.call(mode: "upload")
          assert_equal 1, result.value![:dispatched]
        end
      end
    end

    test "upload mode job has correct relay_url" do
      with_fake_configuration(upload: [ @upload_relay ]) do
        DispatchSyncJobs.call(mode: "upload")

        enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::UploadJob" }
        assert_not_nil enqueued_job
        args = enqueued_job["arguments"].first
        assert_equal "wss://upload.relay.com", args["relay_url"]
      end
    end

    # =========================================================================
    # Skip Already Syncing
    # =========================================================================

    test "skips relay that is already syncing" do
      # Create an active sync state
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      SyncState.create!(
        relay_url: @negentropy_relay.url,
        filter_hash:,
        direction: "down",
        status: "syncing",
        events_downloaded: 0,
        events_uploaded: 0
      )

      with_fake_configuration(backfill: [ @negentropy_relay ]) do
        assert_no_enqueued_jobs only: Sync::NegentropyJob do
          result = DispatchSyncJobs.call(mode: "backfill")
          assert_equal 0, result.value![:dispatched]
        end
      end
    end

    test "dispatches job for stale syncing state" do
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      SyncState.create!(
        relay_url: @negentropy_relay.url,
        filter_hash:,
        direction: "down",
        status: "syncing",
        updated_at: 1.hour.ago, # Stale
        events_downloaded: 0,
        events_uploaded: 0
      )

      with_fake_configuration(backfill: [ @negentropy_relay ]) do
        assert_enqueued_with(job: Sync::NegentropyJob) do
          result = DispatchSyncJobs.call(mode: "backfill")
          assert_equal 1, result.value![:dispatched]
        end
      end
    end

    # =========================================================================
    # Skip Completed Backfill
    # =========================================================================

    test "skips relay with completed backfill" do
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      SyncState.create!(
        relay_url: @negentropy_relay.url,
        filter_hash:,
        direction: "down",
        status: "completed",
        backfill_target: 1.week.ago,
        backfill_until: 2.weeks.ago, # Past target = complete
        events_downloaded: 1000,
        events_uploaded: 0
      )

      with_fake_configuration(backfill: [ @negentropy_relay ]) do
        assert_no_enqueued_jobs only: Sync::NegentropyJob do
          result = DispatchSyncJobs.call(mode: "backfill")
          assert_equal 0, result.value![:dispatched]
        end
      end
    end

    # =========================================================================
    # Single Relay Mode
    # =========================================================================

    test "dispatches job for specific relay when relay_url provided" do
      with_fake_configuration(backfill: [ @negentropy_relay, @polling_relay ]) do
        DispatchSyncJobs.call(mode: "backfill", relay_url: @negentropy_relay.url)

        # Should only enqueue job for the specified relay
        negentropy_jobs = enqueued_jobs.select { |j| j["job_class"] == "Sync::NegentropyJob" }
        polling_jobs = enqueued_jobs.select { |j| j["job_class"] == "Sync::PollingJob" }

        assert_equal 1, negentropy_jobs.size
        assert_equal 0, polling_jobs.size
      end
    end

    # =========================================================================
    # Return Value
    # =========================================================================

    test "returns dispatched count and mode" do
      with_fake_configuration(backfill: [ @negentropy_relay, @polling_relay ]) do
        result = DispatchSyncJobs.call(mode: "backfill")

        assert_equal 2, result.value![:dispatched]
        assert_equal "backfill", result.value![:mode]
      end
    end
  end
end
