# frozen_string_literal: true

require "test_helper"

module Sync
  class OrchestratorJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      # Store original configuration
      @original_config = RelaySync.instance_variable_get(:@configuration)

      # Create empty configuration for tests (no relays = no jobs dispatched)
      empty_config = Object.new
      empty_config.define_singleton_method(:backfill_relays) do [] end
      empty_config.define_singleton_method(:download_relays) do [] end
      empty_config.define_singleton_method(:upload_relays) do [] end
      empty_config.define_singleton_method(:find_relay) do |_url| nil end
      empty_config.define_singleton_method(:sync_settings) do UpstreamRelays::Config.new({}) end

      RelaySync.instance_variable_set(:@configuration, empty_config)
    end

    teardown do
      RelaySync.instance_variable_set(:@configuration, @original_config)
    end

    # =========================================================================
    # Queue Configuration
    # =========================================================================

    test "job is enqueued to sync queue" do
      assert_equal "sync", Sync::OrchestratorJob.new.queue_name
    end

    # =========================================================================
    # Execution
    # =========================================================================

    test "executes without error with no relays configured" do
      assert_nothing_raised do
        Sync::OrchestratorJob.new.perform
      end
    end

    test "executes with realtime mode by default" do
      # With no relays, dispatched should be 0
      assert_nothing_raised do
        Sync::OrchestratorJob.new.perform(mode: "realtime")
      end
    end

    test "executes with backfill mode" do
      assert_nothing_raised do
        Sync::OrchestratorJob.new.perform(mode: "backfill")
      end
    end

    test "executes with upload mode" do
      assert_nothing_raised do
        Sync::OrchestratorJob.new.perform(mode: "upload")
      end
    end

    # =========================================================================
    # Job Enqueueing
    # =========================================================================

    test "can be enqueued with perform_later" do
      assert_enqueued_with(job: Sync::OrchestratorJob, queue: "sync") do
        Sync::OrchestratorJob.perform_later(mode: "realtime")
      end
    end

    test "enqueued job preserves mode argument" do
      Sync::OrchestratorJob.perform_later(mode: "backfill")

      enqueued_job = enqueued_jobs.find { |j| j["job_class"] == "Sync::OrchestratorJob" }
      assert_not_nil enqueued_job
      assert_equal "backfill", enqueued_job["arguments"].first["mode"]
    end
  end
end
