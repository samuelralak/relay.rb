# frozen_string_literal: true

# Recurring job that detects and recovers stale/errored sync operations
# Scheduled via config/recurring.yml
class StaleSyncRecoveryJob < ApplicationJob
  queue_as :sync

  def perform
    Rails.logger.debug "[StaleSyncRecoveryJob] Checking for stale syncs..."

    result = Sync::RecoverStale.call
    values = result.value!

    if values[:recovered_stale] > 0 || values[:retried_errors] > 0
      Rails.logger.info "[StaleSyncRecoveryJob] Recovered: #{values[:recovered_stale]} stale, #{values[:retried_errors]} errors"
    end
  rescue StandardError => e
    Rails.logger.error "[StaleSyncRecoveryJob] Error during recovery: #{e.message}"
    raise
  end
end
