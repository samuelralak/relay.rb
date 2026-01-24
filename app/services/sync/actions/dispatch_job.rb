# frozen_string_literal: true

module Sync
  module Actions
    # Dispatches a single sync job for a relay with duplicate checking.
    class DispatchJob < BaseService
      option :relay, type: Types::Any
      option :mode, type: RelaySync::Types::SyncMode
      option :sync_settings, type: Types::Any, default: -> { RelaySync.configuration.sync_settings }

      def call
        return Failure(:relay_disabled) unless relay.enabled?
        return Failure(:already_syncing) if already_syncing?
        return Failure(:backfill_complete) if backfill_complete?

        dispatch_job
        Success(relay_url: relay.url, mode:)
      end

      private

      def dispatch_job
        case mode
        when RelaySync::SyncMode::BACKFILL, RelaySync::SyncMode::FULL
          dispatch_download_job
        when RelaySync::SyncMode::REALTIME
          dispatch_realtime_job
        when RelaySync::SyncMode::UPLOAD
          dispatch_upload_job if relay.upload_enabled?
        end
      end

      def dispatch_download_job
        if relay.negentropy?
          Sync::NegentropyJob.perform_later(
            relay_url: relay.url,
            filter: {},
            direction: relay.direction,
            backfill_target: backfill_target_timestamp,
            chunk_hours: sync_settings.negentropy_chunk_hours
          )
        else
          filter = mode == RelaySync::SyncMode::FULL ? {} : backfill_filter
          Sync::PollingJob.perform_later(
            relay_url: relay.url,
            filter:,
            mode:
          )
        end
      end

      def dispatch_realtime_job
        Sync::PollingJob.perform_later(
          relay_url: relay.url,
          filter: realtime_filter,
          mode: RelaySync::SyncMode::REALTIME
        )
      end

      def dispatch_upload_job
        Sync::UploadJob.perform_later(relay_url: relay.url)
      end

      def already_syncing?
        return false unless sync_state
        sync_state.syncing? && !sync_state.stale?(threshold: stale_threshold)
      end

      def backfill_complete?
        sync_state&.backfill_complete?
      end

      def sync_state
        @sync_state ||= SyncState.find_by(relay_url: relay.url, filter_hash:)
      end

      def filter_hash
        if mode == RelaySync::SyncMode::UPLOAD
          "upload"
        else
          # All download jobs use direction: "down" for filter_hash consistency
          SyncState.compute_filter_hash(direction: "down", filter: {})
        end
      end

      def backfill_filter
        { since: sync_settings.backfill_since.seconds.ago.to_i }
      end

      def realtime_filter
        { since: sync_settings.polling_window_minutes.minutes.ago.to_i }
      end

      def backfill_target_timestamp
        sync_settings.backfill_since.seconds.ago.to_i
      end

      def stale_threshold
        sync_settings.stale_threshold_minutes.minutes
      end
    end
  end
end
