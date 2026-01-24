# frozen_string_literal: true

module Sync
  # Performs Negentropy (NIP-77) set reconciliation with a remote relay
  class StartNegentropy < BaseService
    SYNC_TIMEOUT = 300 # seconds (5 minutes for large syncs)

    option :relay_url, type: Types::RelayUrl
    option :filter, type: Types::FilterHash, default: -> { {} }
    option :direction, type: Types::Direction, default: -> { "down" }
    option :manage_status, type: Types::Bool, default: -> { true }

    def call
      validate_connection!

      @have_ids = []
      @need_ids = []
      @complete = false
      @error = nil
      @mutex = Mutex.new
      @condition = ConditionVariable.new

      sync_state.mark_syncing! if manage_status
      perform_sync

      { have_ids: @have_ids, need_ids: @need_ids, sync_state: }
    rescue StandardError => e
      sync_state&.mark_error!(e.message) if manage_status
      raise
    end

    private

    def validate_connection!
      raise RelaySync::ConnectionError, "Not connected to #{relay_url}" unless connection&.connected?
    end

    def connection
      @connection ||= RelaySync.manager.connection_for(relay_url)
    end

    def sync_state
      # Use "down" for filter_hash consistency - ensures one SyncState per relay for downloads
      # The `direction` option is still used for should_download?/should_upload? logic
      @sync_state ||= SyncState.for_sync(
        relay_url:,
        direction: "down",
        filter:
      )
    end

    def perform_sync
      storage = build_local_storage
      frame_size = RelaySync.configuration.sync_settings.negentropy_frame_size
      reconciler = Negentropy::Reconciler::Client.new(storage:, frame_size_limit: frame_size)

      subscription_id = "neg_#{SecureRandom.hex(8)}"

      error_callback = ->(error_message) { handle_neg_error(error_message) }

      RelaySync.manager.register_neg_handler(
        subscription_id,
        reconciler:,
        error_callback:
      ) do |have_ids, need_ids, complete|
        handle_reconcile_result(have_ids, need_ids, complete)
      end

      begin
        initial_message = reconciler.initiate
        connection.neg_open(subscription_id, filter, initial_message)

        completed = wait_for_completion

        # Check for errors first (NEG-ERR sets @error and @complete)
        if @error
          connection.neg_close(subscription_id)
          raise RelaySync::NegentropyError, @error
        end

        unless completed
          connection.neg_close(subscription_id)
          # Always raise on timeout so calling code knows the sync failed
          raise RelaySync::SyncTimeoutError, "Sync timeout after #{SYNC_TIMEOUT}s"
        end

        process_sync_results
        # Reset to idle - this service doesn't track backfill state
        # The calling job (NegentropySyncJob) manages completed status when backfill is done
        sync_state.reset_to_idle! if manage_status
      ensure
        RelaySync.manager.unregister_neg_handler(subscription_id)
      end
    end

    def handle_neg_error(error_message)
      @mutex.synchronize do
        @error = error_message
        @complete = true  # Signal completion so we stop waiting
        @condition.broadcast
      end
    end

    def handle_reconcile_result(have_ids, need_ids, complete)
      @mutex.synchronize do
        @have_ids.concat(have_ids)
        @need_ids.concat(need_ids)

        if complete
          @complete = true
          @condition.broadcast
        end
      end
    end

    def wait_for_completion
      deadline = Time.now + SYNC_TIMEOUT

      @mutex.synchronize do
        until @complete
          remaining = deadline - Time.now
          if remaining <= 0
            Rails.logger.warn "[StartNegentropy] Timeout waiting for completion (#{SYNC_TIMEOUT}s elapsed)"
            return false
          end

          # Wait with a maximum of 30 seconds per iteration to ensure we check the deadline
          wait_time = [ remaining, 30 ].min
          @condition.wait(@mutex, wait_time)
        end
        true
      end
    end

    def process_sync_results
      Rails.logger.info "[StartNegentropy] process_sync_results: have_ids=#{@have_ids.size}, need_ids=#{@need_ids.size}"
      Rails.logger.info "[StartNegentropy] direction=#{direction}, should_download?=#{should_download?}"

      # Download events we need (if direction allows)
      if should_download? && @need_ids.any?
        Rails.logger.info "[StartNegentropy] Fetching #{@need_ids.size} missing events"
        result = Sync::FetchMissingEvents.call(
          connection:,
          event_ids: @need_ids,
          batch_size: RelaySync.configuration.sync_settings.batch_size,
          sync_state:  # Pass sync_state for incremental counting per batch
        )
        Rails.logger.info "[StartNegentropy] FetchMissingEvents result: #{result.inspect}"
        # Note: FetchMissingEvents now handles incremental counting per batch
        # This is more robust - counts persist even if connection drops mid-sync
      else
        Rails.logger.info "[StartNegentropy] Skipping fetch: should_download?=#{should_download?}, need_ids.any?=#{@need_ids.any?}"
      end

      # Upload events we have that remote needs (if direction allows)
      if should_upload? && @have_ids.any?
        events = Event.where(event_id: @have_ids).active
        if events.any?
          UploadEventsJob.perform_later(
            relay_url:,
            record_ids: events.pluck(:id)
          )
        end
      end
    end

    def build_local_storage
      scope = Event.active

      scope = scope.where(kind: filter[:kinds]) if filter[:kinds].present?
      scope = scope.where("nostr_created_at >= ?", Time.at(filter[:since]).utc) if filter[:since].present?
      scope = scope.where("nostr_created_at <= ?", Time.at(filter[:until]).utc) if filter[:until].present?
      scope = scope.where(pubkey: filter[:authors]) if filter[:authors].present?

      Negentropy::Storage.from_scope(scope)
    end

    def should_download?
      %w[down both].include?(direction)
    end

    def should_upload?
      %w[up both].include?(direction)
    end
  end
end
