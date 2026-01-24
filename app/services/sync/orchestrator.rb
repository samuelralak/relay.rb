# frozen_string_literal: true

module Sync
  # Central orchestrator that dispatches sync jobs based on relay configuration and SyncState
  # Called by SyncOrchestratorJob (recurring) or manually via rake tasks
  class Orchestrator < BaseService
    option :mode, type: RelaySync::Types::SyncMode
    option :relay_url, type: Types::RelayUrl.optional, default: -> { nil }

    def call
      @dispatched = 0

      if relay_url
        dispatch_for_relay(relay_url)
      else
        case mode
        when RelaySync::SyncMode::BACKFILL then dispatch_backfill_jobs
        when RelaySync::SyncMode::REALTIME then dispatch_realtime_jobs
        when RelaySync::SyncMode::FULL then dispatch_full_sync_jobs
        when RelaySync::SyncMode::UPLOAD then dispatch_upload_jobs
        end
      end

      { dispatched: @dispatched, mode: }
    end

    private

    def dispatch_for_relay(url)
      relay = RelaySync.configuration.find_relay(url)
      return unless relay&.enabled?

      case mode
      when RelaySync::SyncMode::BACKFILL, RelaySync::SyncMode::FULL
        dispatch_download_job(relay, mode)
      when RelaySync::SyncMode::REALTIME
        dispatch_realtime_job(relay)
      when RelaySync::SyncMode::UPLOAD
        dispatch_upload_job(relay) if relay.upload_enabled?
      end
    end

    def dispatch_backfill_jobs
      RelaySync.configuration.backfill_relays.each do |relay|
        dispatch_download_job(relay, RelaySync::SyncMode::BACKFILL)
      end
    end

    def dispatch_realtime_jobs
      RelaySync.configuration.download_relays.each do |relay|
        dispatch_realtime_job(relay)
      end
    end

    def dispatch_full_sync_jobs
      RelaySync.configuration.backfill_relays.each do |relay|
        dispatch_download_job(relay, RelaySync::SyncMode::FULL)
      end
    end

    def dispatch_upload_jobs
      RelaySync.configuration.upload_relays.each do |relay|
        dispatch_upload_job(relay)
      end
    end

    def dispatch_download_job(relay, sync_mode)
      # All download jobs use direction: "down" for filter_hash consistency
      # This ensures one SyncState per relay for downloads, regardless of relay.direction
      # The relay.direction is still passed to the job for upload behavior
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      return if already_syncing?(relay.url, filter_hash)

      if relay.negentropy?
        NegentropySyncJob.perform_later(
          relay_url: relay.url,
          filter: {},
          direction: relay.direction,
          backfill_target: backfill_target_timestamp,
          chunk_hours: sync_settings.negentropy_chunk_hours
        )
      else
        filter = sync_mode == RelaySync::SyncMode::FULL ? full_sync_filter : backfill_filter
        PollingSyncJob.perform_later(
          relay_url: relay.url,
          filter:,
          mode: sync_mode
        )
      end

      @dispatched += 1
    end

    def dispatch_realtime_job(relay)
      # Realtime uses same filter_hash as backfill - one SyncState per relay for downloads
      filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})
      return if already_syncing?(relay.url, filter_hash)

      PollingSyncJob.perform_later(
        relay_url: relay.url,
        filter: realtime_filter,
        mode: RelaySync::SyncMode::REALTIME
      )

      @dispatched += 1
    end

    def dispatch_upload_job(relay)
      return if already_syncing?(relay.url, RelaySync::SyncMode::UPLOAD)

      UploadSyncJob.perform_later(relay_url: relay.url)
      @dispatched += 1
    end

    def already_syncing?(relay_url, filter_hash)
      state = SyncState.find_by(relay_url:, filter_hash:)
      return false unless state

      # Skip if currently syncing and not stale
      if state.syncing? && !state.stale?(threshold: stale_threshold)
        Rails.logger.debug "[Sync::Orchestrator] Skipping #{relay_url} - already syncing"
        return true
      end

      # Skip if backfill is complete (for negentropy jobs)
      if state.backfill_complete?
        Rails.logger.debug "[Sync::Orchestrator] Skipping #{relay_url} - backfill complete"
        return true
      end

      false
    end

    def backfill_filter
      # No kinds filter - sync all event types
      { since: sync_settings.backfill_since.seconds.ago.to_i }
    end

    def backfill_target_timestamp
      sync_settings.backfill_since.seconds.ago.to_i
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

    def stale_threshold
      sync_settings.stale_threshold_minutes.minutes
    end

    def sync_settings
      RelaySync.configuration.sync_settings
    end
  end
end
