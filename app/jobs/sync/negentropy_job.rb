# frozen_string_literal: true

module Sync
  # Performs Negentropy (NIP-77) sync with a remote relay
  # Supports progressive chunked backfill to avoid "too many results" errors
  class NegentropyJob < ApplicationJob
    queue_as :sync

    # Retry on connection errors with exponential backoff
    retry_on RelaySync::ConnectionError, wait: :polynomially_longer, attempts: 5

    # @param relay_url [String] URL of the relay to sync with
    # @param filter [Hash] Nostr filter for events to sync (kinds, authors, etc.)
    # @param direction [String] sync direction (down, up, both)
    # @param backfill_target [Integer] Unix timestamp of oldest events to sync (e.g., 5 years ago)
    # @param chunk_hours [Integer] Size of each sync chunk in hours
    # @param continuation [Boolean] If true, this is a self-scheduled continuation (bypasses syncing check)
    def perform(relay_url:, filter: {}, direction: "down", backfill_target: nil, chunk_hours: 168, continuation: false)
      @relay_url = relay_url
      @direction = direction
      @base_filter = filter.symbolize_keys
      @backfill_target = backfill_target ? Time.at(backfill_target) : 1.week.ago
      @chunk_hours = chunk_hours

      # Find or create sync state for this relay/filter combination
      @sync_state = find_or_create_sync_state

      # Skip if already syncing and not stale (unless this is a continuation)
      unless continuation
        if @sync_state.syncing? && !@sync_state.stale?(threshold: stale_threshold)
          Rails.logger.info "[Sync::NegentropyJob] Skipping #{relay_url} - already syncing"
          @status_handled = true  # Don't reset - another job owns this status
          return
        end
      end

      # Check for stale sync (interrupted previous run)
      if @sync_state.stale?(threshold: stale_threshold)
        Rails.logger.warn "[Sync::NegentropyJob] Resuming stale sync for #{relay_url}"
        @sync_state.reset_to_idle!
      end

      # Initialize backfill tracking if needed
      @sync_state.initialize_backfill!(target: @backfill_target)

      # Check if backfill is already complete
      if @sync_state.backfill_complete?
        Rails.logger.info "[Sync::NegentropyJob] Backfill complete for #{relay_url}"
        # Ensure status reflects completion (might be stale "syncing" from crashed previous job)
        @sync_state.mark_completed! unless @sync_state.completed?
        @status_handled = true
        return
      end

      # Get the next chunk to sync (saved as instance var for error handler access)
      @current_chunk = @sync_state.next_backfill_chunk(chunk_hours: @chunk_hours)
      if @current_chunk.nil?
        Rails.logger.info "[Sync::NegentropyJob] No more chunks to sync for #{relay_url}"
        @sync_state.mark_completed!
        @status_handled = true
        return
      end
      effective_filter = @base_filter.merge(@current_chunk)

      Rails.logger.info "[Sync::NegentropyJob] Starting sync with #{relay_url}"
      Rails.logger.info "[Sync::NegentropyJob] Chunk: #{Time.at(@current_chunk[:since])} to #{Time.at(@current_chunk[:until])}"
      Rails.logger.info "[Sync::NegentropyJob] Progress: #{@sync_state.backfill_progress_percent}% complete"

      ensure_connection!(relay_url)

      # Job manages status, not the service
      @sync_state.mark_syncing!

      result = ::Sync::SyncWithNegentropy.call(
        relay_url: @relay_url,
        filter: effective_filter,
        direction: @direction,
        manage_status: false
      )

      # Reload to get updated events_downloaded from SyncWithNegentropy
      @sync_state.reload

      # Mark this chunk as completed
      @sync_state.mark_backfill_chunk_completed!(chunk_start: Time.at(@current_chunk[:since]))

      Rails.logger.info "[Sync::NegentropyJob] Chunk complete for #{relay_url}. " \
                        "Have: #{result.value![:have_ids].size}, Need: #{result.value![:need_ids].size}"
      Rails.logger.info "[Sync::NegentropyJob] Backfill progress: #{@sync_state.backfill_progress_percent}%"

      # Schedule next chunk immediately if backfill not complete
      if @sync_state.backfill_complete?
        Rails.logger.info "[Sync::NegentropyJob] Backfill FULLY COMPLETE for #{relay_url}"
        @sync_state.mark_completed!
        @status_handled = true
      else
        # Keep status as syncing - the continuation job will bypass the syncing check
        # This provides accurate status during multi-chunk backfill
        Rails.logger.info "[Sync::NegentropyJob] Scheduling next chunk for #{relay_url}"
        self.class.perform_later(
          relay_url:,
          filter: @base_filter,
          direction: @direction,
          backfill_target: @backfill_target.to_i,
          chunk_hours: @chunk_hours,
          continuation: true
        )
        @status_handled = true  # Status intentionally left as syncing for continuation
      end
    rescue RelaySync::SyncTimeoutError => e
      Rails.logger.warn "[Sync::NegentropyJob] Timeout for #{relay_url}: #{e.message}"
      @sync_state&.mark_error!(e.message)
      @status_handled = true
      # Don't retry immediately - let the stale recovery job handle it
      # This avoids hammering a slow relay
    rescue RelaySync::NegentropyError => e
      Rails.logger.warn "[Sync::NegentropyJob] Negentropy error for #{relay_url}: #{e.message}"
      Rails.logger.info "[Sync::NegentropyJob] Falling back to polling sync for current chunk"
      @sync_state&.reset_to_idle!
      @status_handled = true

      # Fall back to polling sync with the same chunk time range
      fallback_filter = if @current_chunk
                          @base_filter.merge(@current_chunk)
      else
                          @base_filter.merge(since: @backfill_target.to_i)
      end
      Sync::PollingJob.perform_later(
        relay_url:,
        filter: fallback_filter,
        mode: RelaySync::SyncMode::BACKFILL
      )
    rescue RelaySync::ConnectionError => e
      Rails.logger.error "[Sync::NegentropyJob] Connection error: #{e.message}"
      @sync_state&.mark_error!(e.message)
      @status_handled = true
      raise # Let retry mechanism handle it
    rescue StandardError => e
      Rails.logger.error "[Sync::NegentropyJob] Error: #{e.message}"
      @sync_state&.mark_error!(e.message)
      @status_handled = true
      raise
    ensure
      # Safety net: if status is still 'syncing' and wasn't handled, reset to idle
      # This prevents jobs from leaving status stuck if terminated unexpectedly
      if @sync_state&.syncing? && !@status_handled
        Rails.logger.warn "[Sync::NegentropyJob] Ensure block resetting stuck syncing status for #{@relay_url}"
        @sync_state.reset_to_idle!
      end
    end

    private

    def find_or_create_sync_state
      # Use "down" for filter_hash consistency - ensures one SyncState per relay for downloads
      # The @direction is still used by SyncWithNegentropy for upload behavior
      SyncState.for_sync(
        relay_url: @relay_url,
        direction: "down",
        filter: @base_filter
      )
    end

    def ensure_connection!(relay_url)
      result = ::Sync::Actions::EnsureConnection.call(relay_url:)
      raise RelaySync::ConnectionError, "Failed to connect to #{relay_url}" unless result.success?
    end

    def stale_threshold
      RelaySync.configuration.sync_settings.stale_threshold_minutes.minutes
    end
  end
end
