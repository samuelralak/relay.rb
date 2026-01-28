# frozen_string_literal: true

module Sync
  module Actions
    # Retries "error" states by resetting them to idle after a cooldown period.
    class RetryErroredSyncs < BaseService
      include Loggable

      option :retry_after_seconds, type: Types::Integer.optional, default: -> { nil }

      def call
        retry_after = effective_retry_after
        count = 0

        SyncState.errored.where("updated_at < ?", retry_after.ago).find_each do |state|
          logger.info "Resetting errored sync for retry", relay_url: state.relay_url, filter_hash: state.filter_hash
          logger.info "Previous error", error: state.error_message
          state.reset_to_idle!
          count += 1
        end

        Success(retried: count)
      end

      private

      def effective_retry_after
        if retry_after_seconds
          retry_after_seconds.seconds
        else
          sync_settings.error_retry_after_minutes.minutes
        end
      end

      def sync_settings
        RelaySync.configuration.sync_settings
      end
    end
  end
end
