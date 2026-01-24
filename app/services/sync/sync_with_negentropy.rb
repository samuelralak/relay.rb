# frozen_string_literal: true

module Sync
  # Performs Negentropy (NIP-77) set reconciliation with a remote relay.
  # Downloads events we need and schedules uploads for events we have.
  class SyncWithNegentropy < BaseService
    include Connectionable
    include TimeoutWaitable
    include ErrorHandleable

    option :relay_url, type: Types::RelayUrl
    option :filter, type: Types::FilterHash, default: -> { {} }
    option :direction, type: Types::Direction, default: -> { "down" }
    option :manage_status, type: Types::Bool, default: -> { true }

    def call
      with_error_handling(manage_status:) do
        validate_connection!

        @have_ids = []
        @need_ids = []
        @tracker = create_sync_tracker

        sync_state.mark_syncing! if manage_status
        perform_sync

        Success(have_ids: @have_ids, need_ids: @need_ids, sync_state:)
      end
    end

    private

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
      storage = Actions::BuildStorage.call(filter:).value!
      frame_size = sync_settings.negentropy_frame_size
      reconciler = Negentropy::Reconciler::Client.new(storage:, frame_size_limit: frame_size)

      subscription_id = "#{Constants::SubscriptionPrefixes::NEGENTROPY}#{SecureRandom.hex(Constants::IdLengths::NEGENTROPY_ID)}"

      error_callback = ->(error_message) { @tracker.mark_error!(error_message) }

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

        completed = wait_with_timeout(
          timeout: Constants::Timeouts::NEGENTROPY_SYNC,
          tracker: @tracker
        ) { @tracker.complete_unlocked? }

        # Check for errors first (NEG-ERR sets error and complete)
        if @tracker.error
          connection.neg_close(subscription_id)
          raise RelaySync::NegentropyError, @tracker.error
        end

        unless completed
          connection.neg_close(subscription_id)
          raise RelaySync::SyncTimeoutError, "Sync timeout after #{Constants::Timeouts::NEGENTROPY_SYNC}s"
        end

        process_sync_results
        # Reset to idle - this service doesn't track backfill state
        # The calling job (Sync::NegentropyJob) manages completed status when backfill is done
        sync_state.reset_to_idle! if manage_status
      ensure
        RelaySync.manager.unregister_neg_handler(subscription_id)
      end
    end

    def handle_reconcile_result(have_ids, need_ids, complete)
      @tracker.synchronize do
        @have_ids.concat(have_ids)
        @need_ids.concat(need_ids)
        @tracker.mark_complete_unlocked! if complete
      end
    end

    def process_sync_results
      Rails.logger.info "[SyncWithNegentropy] process_sync_results: have_ids=#{@have_ids.size}, need_ids=#{@need_ids.size}"
      Rails.logger.info "[SyncWithNegentropy] direction=#{direction}, should_download?=#{should_download?}"

      Performers::ProcessReconciliationResults.call(
        connection:,
        relay_url:,
        have_ids: @have_ids,
        need_ids: @need_ids,
        direction:,
        sync_state:
      )
    end

    def should_download?
      %w[down both].include?(direction)
    end

    def should_upload?
      %w[up both].include?(direction)
    end

    def sync_settings
      RelaySync.configuration.sync_settings
    end
  end
end
