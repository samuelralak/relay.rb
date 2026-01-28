# frozen_string_literal: true

module Sync
  # Recurring job that detects and recovers stale/errored sync operations
  # Scheduled via config/recurring.yml
  class RecoveryJob < ApplicationJob
    include JobLoggable

    queue_as :sync

    def perform
      logger.debug "Checking for stale syncs..."

      result = ::Sync::RecoverStale.call
      values = result.value!

      if values[:recovered_stale] > 0 || values[:retried_errors] > 0
        logger.info "Recovered syncs",
          stale: values[:recovered_stale],
          errors: values[:retried_errors]
      end
    rescue StandardError => e
      logger.error "Error during recovery", error: e.message
      raise
    end
  end
end
