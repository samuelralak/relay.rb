# frozen_string_literal: true

module Sync
  # DEPRECATED: Use Sync::DispatchSyncJobs instead.
  # This alias will be removed in the next major version.
  #
  # Central orchestrator that dispatches sync jobs based on relay configuration.
  # Called by SyncOrchestratorJob (recurring) or manually via rake tasks.
  Orchestrator = DispatchSyncJobs
end
