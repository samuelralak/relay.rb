# frozen_string_literal: true

module Sync
  # Uploads local events to a remote relay
  # Uses SyncState to track upload progress and prevent duplicate uploads
  class UploadJob < ApplicationJob
    include JobLoggable

    queue_as :uploads

    retry_on RelaySync::ConnectionError, wait: :polynomially_longer, attempts: 3

    # @param relay_url [String] URL of the relay to upload to
    def perform(relay_url:)
      @relay_url = relay_url
      @sync_state = find_or_create_sync_state

      # Skip if already syncing and not stale
      if @sync_state.syncing? && !@sync_state.stale?(threshold: stale_threshold)
        logger.info("Skipping - already uploading", relay_url:)
        return
      end

      # Reset stale syncs
      @sync_state.reset_to_idle! if @sync_state.stale?(threshold: stale_threshold)

      # Get events to upload (uses SyncState cursor)
      events_scope = @sync_state.events_to_upload
                                .limit(sync_settings.upload_batch_size)

      if events_scope.empty?
        logger.info("No events to upload", relay_url:)
        return
      end

      logger.info "Uploading events", relay_url:, count: events_scope.count

      @sync_state.mark_syncing!

      result = ::Sync::UploadEvents.call(
        relay_url:,
        record_ids: events_scope.pluck(:id)
      )
      values = result.value!

      # Update cursor to latest uploaded event
      if values[:published] > 0
        latest = events_scope.order(nostr_created_at: :desc).first
        @sync_state.mark_upload_progress!(
          event_id: latest.event_id,
          timestamp: latest.nostr_created_at,
          count: values[:published]
        )
      end

      @sync_state.mark_completed!

      logger.info "Upload completed",
        relay_url:,
        published: values[:published],
        duplicates: values[:duplicates],
        failed: values[:failed]
    rescue StandardError => e
      logger.error "Error uploading", relay_url:, error: e.message
      @sync_state&.mark_error!(e.message)
      raise
    end

    private

    def find_or_create_sync_state
      SyncState.find_or_create_by!(relay_url: @relay_url, filter_hash: "upload") do |state|
        state.direction = "up"
        state.status = "idle"
        state.events_downloaded = 0
        state.events_uploaded = 0
      end
    end

    def stale_threshold
      sync_settings.stale_threshold_minutes.minutes
    end

    def sync_settings
      RelaySync.configuration.sync_settings
    end
  end
end
