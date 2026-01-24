# frozen_string_literal: true

module Sync
  # Dispatches sync jobs based on mode and relay configuration.
  # Called by SyncOrchestratorJob (recurring) or manually via rake tasks.
  class DispatchSyncJobs < BaseService
    option :mode, type: RelaySync::Types::SyncMode
    option :relay_url, type: Types::RelayUrl.optional, default: -> { nil }

    def call
      @dispatched = 0

      if relay_url
        dispatch_for_single_relay
      else
        dispatch_for_all_relays
      end

      Success(dispatched: @dispatched, mode:)
    end

    private

    def dispatch_for_single_relay
      relay = configuration.find_relay(relay_url)
      return unless relay

      result = Actions::DispatchJob.call(relay:, mode:, sync_settings:)
      @dispatched += 1 if result.success?
    end

    def dispatch_for_all_relays
      relays_for_mode.each do |relay|
        result = Actions::DispatchJob.call(relay:, mode:, sync_settings:)
        @dispatched += 1 if result.success?
      end
    end

    def relays_for_mode
      case mode
      when RelaySync::SyncMode::BACKFILL, RelaySync::SyncMode::FULL
        configuration.backfill_relays
      when RelaySync::SyncMode::REALTIME
        configuration.download_relays
      when RelaySync::SyncMode::UPLOAD
        configuration.upload_relays
      else
        []
      end
    end

    def sync_settings
      configuration.sync_settings
    end

    def configuration
      RelaySync.configuration
    end
  end
end
