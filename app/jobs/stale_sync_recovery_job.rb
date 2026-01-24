# frozen_string_literal: true

# Recurring job that detects and recovers stale/errored sync operations
# Scheduled via config/recurring.yml
class StaleSyncRecoveryJob < ApplicationJob
  queue_as :sync

  def perform
    Rails.logger.debug "[StaleSyncRecoveryJob] Checking for stale syncs..."

    result = Sync::RecoverStale.call

    if result[:recovered_stale] > 0 || result[:retried_errors] > 0
      Rails.logger.info "[StaleSyncRecoveryJob] Recovered: #{result[:recovered_stale]} stale, #{result[:retried_errors]} errors"
    end
  rescue StandardError => e
    Rails.logger.error "[StaleSyncRecoveryJob] Error during recovery: #{e.message}"
    raise
  end
end
