# frozen_string_literal: true

module Sync
  # Facade that combines stale recovery and error retry.
  # Maintains backward compatibility with existing callers.
  # Called by Sync::RecoveryJob (recurring) or manually via rake tasks
  class RecoverStale < BaseService
    option :stale_threshold, type: Types::Integer.optional, default: -> { nil }
    option :error_retry_after, type: Types::Integer.optional, default: -> { nil }

    def call
      stale_result = Actions::RecoverStaleSyncs.call(threshold_seconds: stale_threshold)
      error_result = Actions::RetryErroredSyncs.call(retry_after_seconds: error_retry_after)

      Success(
        recovered_stale: stale_result.value![:recovered],
        retried_errors: error_result.value![:retried]
      )
    end
  end
end
