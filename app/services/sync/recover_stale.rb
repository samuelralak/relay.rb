# frozen_string_literal: true

module Sync
  # Detects and recovers stale/errored sync states
  # Called by StaleSyncRecoveryJob (recurring) or manually via rake tasks
  class RecoverStale < BaseService
    option :stale_threshold, type: Types::Integer.optional, default: -> { nil }
    option :error_retry_after, type: Types::Integer.optional, default: -> { nil }

    def call
      recovered_stale = recover_stale_syncs
      retried_errors = retry_errored_syncs

      { recovered_stale: recovered_stale, retried_errors: retried_errors }
    end

    private

    def recover_stale_syncs
      threshold = effective_stale_threshold
      count = 0

      SyncState.syncing.where("updated_at < ?", threshold.ago).find_each do |state|
        Rails.logger.warn "[Sync::RecoverStale] Recovering stale sync: #{state.relay_url} (filter: #{state.filter_hash})"
        state.reset_to_idle!
        count += 1
      end

      count
    end

    def retry_errored_syncs
      retry_after = effective_error_retry_after
      count = 0

      SyncState.errored.where("updated_at < ?", retry_after.ago).find_each do |state|
        Rails.logger.info "[Sync::RecoverStale] Resetting errored sync for retry: #{state.relay_url} (filter: #{state.filter_hash})"
        Rails.logger.info "[Sync::RecoverStale] Previous error: #{state.error_message}"
        state.reset_to_idle!
        count += 1
      end

      count
    end

    def effective_stale_threshold
      if stale_threshold
        stale_threshold.seconds
      else
        sync_settings.stale_threshold_minutes.minutes
      end
    end

    def effective_error_retry_after
      if error_retry_after
        error_retry_after.seconds
      else
        sync_settings.error_retry_after_minutes.minutes
      end
    end

    def sync_settings
      RelaySync.configuration.sync_settings
    end
  end
end
