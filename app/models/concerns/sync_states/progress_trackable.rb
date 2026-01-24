# frozen_string_literal: true

module SyncStates
  # Handles atomic progress updates for sync operations.
  module ProgressTrackable
    extend ActiveSupport::Concern

    def mark_download_progress!(event_id:, timestamp:, count: 1)
      # Use atomic increment to avoid race conditions
      self.class.where(id:).update_all([
        "last_download_event_id = ?, last_download_timestamp = ?, last_synced_at = ?, " \
        "events_downloaded = events_downloaded + ?, updated_at = ?",
        event_id, timestamp, Time.current, count, Time.current
      ])
      reload
    end

    def mark_upload_progress!(event_id:, timestamp:, count: 1)
      # Use atomic increment to avoid race conditions
      self.class.where(id:).update_all([
        "last_upload_event_id = ?, last_upload_timestamp = ?, last_synced_at = ?, " \
        "events_uploaded = events_uploaded + ?, updated_at = ?",
        event_id, timestamp, Time.current, count, Time.current
      ])
      reload
    end

    # Atomically increment events_downloaded counter
    # @param count [Integer] number to add
    def increment_events_downloaded!(count)
      return if count <= 0

      self.class.where(id:).update_all([
        "events_downloaded = events_downloaded + ?, updated_at = ?",
        count, Time.current
      ])
      reload
    end

    # Atomically increment events_uploaded counter
    # @param count [Integer] number to add
    def increment_events_uploaded!(count)
      return if count <= 0

      self.class.where(id:).update_all([
        "events_uploaded = events_uploaded + ?, updated_at = ?",
        count, Time.current
      ])
      reload
    end

    def total_events_synced
      events_downloaded + events_uploaded
    end
  end
end
