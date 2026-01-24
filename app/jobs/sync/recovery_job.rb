# frozen_string_literal: true

module Sync
  # Recurring job that detects and recovers stale/errored sync operations
  # Scheduled via config/recurring.yml
  class RecoveryJob < ApplicationJob
    queue_as :sync

    def perform
      Rails.logger.debug "[Sync::RecoveryJob] Checking for stale syncs..."

      result = ::Sync::RecoverStale.call
      values = result.value!

      if values[:recovered_stale] > 0 || values[:retried_errors] > 0
        Rails.logger.info "[Sync::RecoveryJob] Recovered: #{values[:recovered_stale]} stale, #{values[:retried_errors]} errors"
      end
    rescue StandardError => e
      Rails.logger.error "[Sync::RecoveryJob] Error during recovery: #{e.message}"
      raise
    end
  end
end
