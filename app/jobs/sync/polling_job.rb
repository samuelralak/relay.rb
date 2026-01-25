# frozen_string_literal: true

module Sync
  # Polls a relay for events using REQ/EOSE pattern
  # Supports both realtime polling and chunked backfill modes
  class PollingJob < ApplicationJob
    queue_as :sync

    retry_on RelaySync::ConnectionError, wait: :polynomially_longer, attempts: 5

    # @param relay_url [String] URL of the relay to poll
    # @param filter [Hash] Nostr filter for events to receive
    # @param mode [String] sync mode: "realtime" or "backfill"
    # @param backfill_target [Integer, nil] Unix timestamp of oldest events to sync (nil = realtime mode)
    # @param chunk_hours [Integer] Size of each backfill chunk in hours
    # @param continuation [Boolean] If true, this is a self-scheduled continuation
    def perform(relay_url:, filter: {}, mode: RelaySync::SyncMode::REALTIME,
                backfill_target: nil, chunk_hours: 168, continuation: false)
      @relay_url = relay_url
      @filter = filter.symbolize_keys
      @mode = mode
      @backfill_target = backfill_target ? Time.at(backfill_target) : nil
      @chunk_hours = chunk_hours
      @continuation = continuation
      @events_this_batch = 0
      @latest_timestamp = nil
      @latest_event_id = nil
      @counter_mutex = Mutex.new
      @status_handled = false

      @sync_state = find_or_create_sync_state

      # Skip if already syncing (unless continuation)
      unless @continuation
        if @sync_state.syncing? && !@sync_state.stale?(threshold: stale_threshold)
          Rails.logger.info "[Sync::PollingJob] Skipping #{relay_url} - already syncing"
          @status_handled = true  # Don't reset - another job owns this status
          return
        end
      end

      # Reset stale syncs
      @sync_state.reset_to_idle! if @sync_state.stale?(threshold: stale_threshold)

      # Branch based on mode
      if backfill_mode?
        perform_chunked_backfill
      else
        perform_realtime_poll
      end
    rescue StandardError => e
      Rails.logger.error "[Sync::PollingJob] Error polling #{relay_url}: #{e.message}"
      @sync_state&.mark_error!(e.message)
      @status_handled = true
      raise
    ensure
      # Safety net: if status is still 'syncing' and wasn't handled, reset to idle
      # This prevents jobs from leaving status stuck if terminated unexpectedly
      if @sync_state&.syncing? && !@status_handled
        Rails.logger.warn "[Sync::PollingJob] Ensure block resetting stuck syncing status for #{@relay_url}"
        @sync_state.reset_to_idle!
      end
    end

    private

    def backfill_mode?
      (@mode == RelaySync::SyncMode::BACKFILL || @mode == RelaySync::SyncMode::FULL) &&
        @backfill_target.present?
    end

    def perform_chunked_backfill
      # Initialize polling backfill tracking
      @sync_state.initialize_polling_backfill!(from: @backfill_target)

      # Check if already complete
      if @sync_state.polling_backfill_complete?
        Rails.logger.info "[Sync::PollingJob] Backfill complete for #{@relay_url}"
        @sync_state.mark_completed! unless @sync_state.completed?
        @status_handled = true
        return
      end

      # Get next chunk
      @current_chunk = @sync_state.next_polling_backfill_chunk(chunk_hours: @chunk_hours)
      if @current_chunk.nil?
        Rails.logger.info "[Sync::PollingJob] No more chunks for #{@relay_url}"
        @sync_state.mark_completed!
        @status_handled = true
        return
      end

      # Merge chunk filter with base filter
      effective_filter = @filter.merge(@current_chunk)

      Rails.logger.info "[Sync::PollingJob] Backfill chunk: #{Time.at(@current_chunk[:since])} to #{Time.at(@current_chunk[:until])}"
      Rails.logger.info "[Sync::PollingJob] Progress: #{@sync_state.polling_backfill_progress_percent}%"

      ensure_connection!
      @sync_state.mark_syncing!

      # Poll events for this chunk
      events_received = poll_events(effective_filter)

      # Mark chunk completed
      @sync_state.mark_polling_chunk_completed!(chunk_end: Time.at(@current_chunk[:until]))

      Rails.logger.info "[Sync::PollingJob] Chunk complete: #{events_received} events"

      # Schedule next chunk or mark completed
      if @sync_state.polling_backfill_complete?
        Rails.logger.info "[Sync::PollingJob] Backfill FULLY COMPLETE for #{@relay_url}"
        @sync_state.mark_completed!
        @status_handled = true
      else
        Rails.logger.info "[Sync::PollingJob] Scheduling next chunk"
        self.class.perform_later(
          relay_url: @relay_url,
          filter: @filter,
          mode: @mode,
          backfill_target: @backfill_target.to_i,
          chunk_hours: @chunk_hours,
          continuation: true
        )
        @status_handled = true  # Status intentionally left as syncing for continuation
      end
    end

    def perform_realtime_poll
      # Build effective filter with resume logic
      effective_filter = @sync_state.resume_filter(
        base_filter: @filter,
        fallback_since: @filter[:since]
      )

      Rails.logger.info "[Sync::PollingJob] Polling #{@relay_url} (mode: #{@mode})"
      Rails.logger.info "[Sync::PollingJob] Filter: #{effective_filter}"

      ensure_connection!
      @sync_state.mark_syncing!

      events_received = poll_events(effective_filter)

      # Reset to idle - polling is incremental, not a complete backfill
      # The sync will be picked up again by the next scheduled orchestration
      @sync_state.reset_to_idle!
      @status_handled = true
      Rails.logger.info "[Sync::PollingJob] Finished polling #{@relay_url}: #{events_received} events received"
    end

    def find_or_create_sync_state
      # Use centralized method for consistent filter_hash calculation
      # Mode (backfill/realtime) is for logging only - same SyncState is used
      SyncState.for_sync(
        relay_url: @relay_url,
        direction: "down",
        filter: @filter
      )
    end

    def ensure_connection!
      result = ::Sync::Actions::EnsureConnection.call(relay_url: @relay_url)
      raise RelaySync::ConnectionError, "Failed to connect to #{@relay_url}" unless result.success?
    end

    def handle_event(event_data)
      # Track progress with cursor
      timestamp = event_data["created_at"] || event_data[:created_at]
      event_id = event_data["id"] || event_data[:id]

      should_checkpoint = false
      @counter_mutex.synchronize do
        @events_this_batch += 1
        @latest_timestamp = timestamp
        @latest_event_id = event_id
        should_checkpoint = (@events_this_batch % checkpoint_interval == 0)
      end

      # Update cursor periodically (every N events per config)
      if should_checkpoint
        @sync_state.mark_download_progress!(
          event_id:,
          timestamp: Time.at(timestamp),
          count: checkpoint_interval
        )
      end

      # Queue event for processing - broadcast only for realtime sync
      Events::ProcessJob.perform_later(event_data.to_json, @relay_url, broadcast: realtime_mode?)
    end

    def realtime_mode?
      @mode == RelaySync::SyncMode::REALTIME
    end

    def connection
      RelaySync.manager.connection_for(@relay_url)
    end

    def poll_events(filter)
      sub_id = "poll_#{SecureRandom.hex(8)}"
      eose_received = false
      mutex = Mutex.new
      condition = ConditionVariable.new

      # Register event handler for this specific subscription
      RelaySync.manager.register_event_handler(sub_id) do |conn, subscription_id, event_data|
        handle_event(event_data)
      end

      # Register EOSE handler to know when historical events are done
      RelaySync.manager.register_eose_handler(sub_id) do
        mutex.synchronize do
          eose_received = true
          condition.broadcast
        end
      end

      begin
        # Send subscription request
        connection.subscribe(sub_id, [ filter ])

        # Wait for EOSE (End of Stored Events)
        mutex.synchronize do
          deadline = Time.now + poll_timeout
          until eose_received
            remaining = deadline - Time.now
            break if remaining <= 0
            condition.wait(mutex, remaining)
          end
        end

        # Final cursor update for remaining events
        update_final_cursor

      ensure
        # Always clean up subscription and handlers
        connection.unsubscribe(sub_id) if connection&.connected?
        RelaySync.manager.unregister_event_handler(sub_id)
        RelaySync.manager.unregister_eose_handler(sub_id)
      end

      @events_this_batch
    end

    def update_final_cursor
      event_id, timestamp, remaining = @counter_mutex.synchronize {
        return unless @latest_event_id && @events_this_batch > 0
        [ @latest_event_id, @latest_timestamp, @events_this_batch % checkpoint_interval ]
      }

      if remaining && remaining > 0
        @sync_state.mark_download_progress!(
          event_id:,
          timestamp: Time.at(timestamp),
          count: remaining
        )
      end
    end

    def poll_timeout
      sync_settings.polling_timeout_seconds
    end

    def stale_threshold
      sync_settings.stale_threshold_minutes.minutes
    end

    def checkpoint_interval
      sync_settings.checkpoint_interval
    end

    def sync_settings
      RelaySync.configuration.sync_settings
    end
  end
end
