# frozen_string_literal: true

module Sync
  # Recurring job that orchestrates sync across all configured relays
  # Scheduled via config/recurring.yml with different modes
  class OrchestratorJob < ApplicationJob
    queue_as :sync

    # @param mode [String] sync mode: "realtime", "backfill", "full", or "upload"
    def perform(mode: RelaySync::SyncMode::REALTIME)
      Rails.logger.info "[Sync::OrchestratorJob] Starting orchestration (mode: #{mode})"

      result = ::Sync::DispatchSyncJobs.call(mode:)

      Rails.logger.info "[Sync::OrchestratorJob] Dispatched #{result.value![:dispatched]} sync job(s)"
    rescue StandardError => e
      Rails.logger.error "[Sync::OrchestratorJob] Error during orchestration: #{e.message}"
      raise
    end
  end
end
