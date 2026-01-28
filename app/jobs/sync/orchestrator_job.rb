# frozen_string_literal: true

module Sync
  # Recurring job that orchestrates sync across all configured relays
  # Scheduled via config/recurring.yml with different modes
  class OrchestratorJob < ApplicationJob
    include JobLoggable

    queue_as :sync

    # @param mode [String] sync mode: "realtime", "backfill", "full", or "upload"
    def perform(mode: RelaySync::SyncMode::REALTIME)
      logger.info("Starting orchestration", mode:)

      result = ::Sync::DispatchSyncJobs.call(mode:)

      logger.info "Dispatched sync jobs", count: result.value![:dispatched]
    rescue StandardError => e
      logger.error "Error during orchestration", error: e.message
      raise
    end
  end
end
