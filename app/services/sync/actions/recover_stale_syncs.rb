# frozen_string_literal: true

module Sync
  module Actions
    # Resets stuck "syncing" states back to idle.
    # States are considered stale if they've been syncing longer than the threshold.
    class RecoverStaleSyncs < BaseService
      include Loggable

      option :threshold_seconds, type: Types::Integer.optional, default: -> { nil }

      def call
        threshold = effective_threshold
        count = 0

        SyncState.syncing.where("updated_at < ?", threshold.ago).find_each do |state|
          logger.warn "Recovering stale sync", relay_url: state.relay_url, filter_hash: state.filter_hash
          state.reset_to_idle!
          count += 1
        end

        Success(recovered: count)
      end

      private

      def effective_threshold
        if threshold_seconds
          threshold_seconds.seconds
        else
          sync_settings.stale_threshold_minutes.minutes
        end
      end

      def sync_settings
        RelaySync.configuration.sync_settings
      end
    end
  end
end
