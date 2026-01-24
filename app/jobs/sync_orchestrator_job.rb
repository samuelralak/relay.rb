# frozen_string_literal: true

# Recurring job that orchestrates sync across all configured relays
# Scheduled via config/recurring.yml with different modes
class SyncOrchestratorJob < ApplicationJob
  queue_as :sync

  # @param mode [String] sync mode: "realtime", "backfill", "full", or "upload"
  def perform(mode: RelaySync::SyncMode::REALTIME)
    Rails.logger.info "[SyncOrchestratorJob] Starting orchestration (mode: #{mode})"

    result = Sync::DispatchSyncJobs.call(mode:)

    Rails.logger.info "[SyncOrchestratorJob] Dispatched #{result.value![:dispatched]} sync job(s)"
  rescue StandardError => e
    Rails.logger.error "[SyncOrchestratorJob] Error during orchestration: #{e.message}"
    raise
  end
end
