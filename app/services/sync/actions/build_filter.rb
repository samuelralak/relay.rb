# frozen_string_literal: true

module Sync
  module Actions
    # Builds Nostr filters for various sync modes.
    class BuildFilter < BaseService
      option :mode, type: RelaySync::Types::SyncMode
      option :sync_settings, type: Types::Any, default: -> { RelaySync.configuration.sync_settings }

      def call
        filter = case mode
        when RelaySync::SyncMode::BACKFILL
                   backfill_filter
        when RelaySync::SyncMode::REALTIME
                   realtime_filter
        when RelaySync::SyncMode::FULL
                   full_sync_filter
        else
                   {}
        end

        Success(filter)
      end

      private

      def backfill_filter
        # No kinds filter - sync all event types
        { since: sync_settings.backfill_since.seconds.ago.to_i }
      end

      def realtime_filter
        # No kinds filter - sync all event types
        { since: polling_window.ago.to_i }
      end

      def full_sync_filter
        # No filters - compare entire sets, all event types
        {}
      end

      def polling_window
        sync_settings.polling_window_minutes.minutes
      end
    end
  end
end
