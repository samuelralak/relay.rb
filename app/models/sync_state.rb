# frozen_string_literal: true

# Tracks sync progress for a relay+filter combination.
#
# == Status Lifecycle
#
# The status field represents the current state of sync operations:
#
#   +-------+     start sync     +---------+
#   | idle  | -----------------> | syncing |
#   +-------+                    +---------+
#       ^                            |
#       |   reset/interrupted        |
#       +----------------------------+
#       |                            |
#       |                            v
#   +-------+    backfill done   +-----------+
#   | error | <--- failure ---   | completed |
#   +-------+                    +-----------+
#
# === Status Definitions
#
# [idle]
#   Ready for sync. This is the initial state and the state after:
#   - A polling sync finishes (polling is incremental, not complete)
#   - A Negentropy chunk completes but backfill continues
#   - Recovery from a stale or interrupted sync
#   - Manual reset
#
#   Jobs in this state will be picked up by the next SyncOrchestratorJob.
#
# [syncing]
#   Sync is actively running. Only one sync should run per relay at a time.
#   The `updated_at` timestamp is used to detect stale syncs (jobs that
#   crashed without cleanup). Syncs older than `stale_threshold_minutes`
#   are considered stale and will be reset to idle by StaleSyncRecoveryJob.
#
# [completed]
#   Backfill is fully complete (reached the target timestamp).
#   This status should ONLY be set when `backfill_complete?` returns true.
#   Once completed, the relay won't receive new backfill jobs - only
#   realtime polling for new events.
#
# [error]
#   Sync failed with an error. The `error_message` field contains details.
#   Errored syncs will be retried after `error_retry_after_minutes` by
#   StaleSyncRecoveryJob, which resets them to idle.
#
# == Backfill Tracking
#
# For progressive backfill (chunked sync going backwards in time):
#
# - `backfill_target`: The oldest timestamp to sync to (e.g., 5 years ago)
# - `backfill_until`: Current progress marker, working backwards from now
# - `backfill_complete?`: True when backfill_until <= backfill_target
# - `backfill_progress_percent`: Visual progress indicator
#
# == Filter Hash
#
# Each SyncState is uniquely identified by relay_url + filter_hash.
# The filter_hash is computed from direction + filter (excluding since/until)
# to ensure consistent state tracking across restarts.
#
class SyncState < ApplicationRecord
  STATUSES = %w[idle syncing completed error].freeze
  DIRECTIONS = %w[down up both].freeze

  # Compute a stable filter_hash for a given direction and filter
  # This ensures one SyncState per relay+direction+filter combination
  # @param direction [String] "down", "up", or "both"
  # @param filter [Hash] optional filter criteria (kinds, authors, etc.)
  # @return [String] 16-character hex hash
  def self.compute_filter_hash(direction:, filter: {})
    stable_filter = filter.except(:since, :until).symbolize_keys
    # Sort keys to ensure consistent ordering
    sorted_filter = stable_filter.sort.to_h
    Digest::SHA256.hexdigest("#{direction}:#{sorted_filter.to_json}")[0, 16]
  end

  # Find or create a SyncState for the given relay and parameters
  # @param relay_url [String] the relay URL
  # @param direction [String] "down", "up", or "both"
  # @param filter [Hash] optional filter criteria
  # @return [SyncState]
  def self.for_sync(relay_url:, direction:, filter: {})
    filter_hash = compute_filter_hash(direction:, filter:)

    find_or_create_by!(relay_url:, filter_hash:) do |state|
      state.direction = direction
      state.status = "idle"
      state.events_downloaded = 0
      state.events_uploaded = 0
    end
  rescue ActiveRecord::RecordNotUnique
    # Handle race condition: another process created the record simultaneously
    # Simply find and return the existing record
    find_by!(relay_url:, filter_hash:)
  end

  validates :relay_url, presence: true, uniqueness: { scope: :filter_hash }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :direction, presence: true, inclusion: { in: DIRECTIONS }
  validates :events_downloaded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :events_uploaded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_relay, ->(url) { where(relay_url: url) }
  scope :active, -> { where(status: %w[idle syncing]) }
  scope :needs_sync, -> { where(status: "idle") }
  scope :syncing, -> { where(status: "syncing") }
  scope :completed, -> { where(status: "completed") }
  scope :errored, -> { where(status: "error") }
  scope :downloads, -> { where(direction: %w[down both]) }
  scope :uploads, -> { where(direction: %w[up both]) }

  def mark_syncing!
    update!(status: "syncing", error_message: nil)
  end

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

  def mark_completed!
    update!(status: "completed", error_message: nil)
  end

  def mark_error!(message)
    update!(status: "error", error_message: message)
  end

  def reset_to_idle!
    update!(status: "idle", error_message: nil)
  end

  def download_enabled?
    direction.in?(%w[down both])
  end

  def upload_enabled?
    direction.in?(%w[up both])
  end

  def idle?
    status == "idle"
  end

  def syncing?
    status == "syncing"
  end

  def error?
    status == "error"
  end

  def completed?
    status == "completed"
  end

  def download_filter(base_filter = {})
    filter = base_filter.dup
    filter[:since] = last_download_timestamp.to_i if last_download_timestamp
    filter
  end

  # Returns a filter for resuming sync with overlap to prevent gaps
  # @param base_filter [Hash] base filter to merge with
  # @param overlap_seconds [Integer] how far back to go from last cursor (default from config)
  # @param fallback_since [Integer] timestamp to use if no cursor exists
  def resume_filter(base_filter: {}, overlap_seconds: nil, fallback_since: nil)
    overlap = overlap_seconds || RelaySync.configuration.sync_settings.resume_overlap_seconds
    filter = base_filter.dup

    if last_download_timestamp
      # Resume from cursor minus overlap to ensure no gaps
      resumed_since = last_download_timestamp.to_i - overlap
      filter[:since] = resumed_since
      Rails.logger.info "[SyncState] Resuming from #{Time.at(resumed_since)} (cursor - #{overlap}s overlap)"
    elsif fallback_since
      # First sync - use fallback
      filter[:since] = fallback_since
      Rails.logger.info "[SyncState] Starting fresh from #{Time.at(fallback_since)}"
    else
      # No resume point - this will sync all events (potentially expensive)
      Rails.logger.warn "[SyncState] No resume point for #{relay_url} - syncing without time filter"
    end

    filter
  end

  # Check if this sync has made progress and can be resumed
  def resumable?
    last_download_timestamp.present? || last_upload_timestamp.present?
  end

  # Check if sync was interrupted (marked syncing but no recent activity)
  def stale?(threshold: 5.minutes)
    syncing? && updated_at < threshold.ago
  end

  def events_to_upload
    scope = Event.active.newest_first
    scope = scope.where("nostr_created_at > ?", last_upload_timestamp) if last_upload_timestamp
    scope
  end

  def total_events_synced
    events_downloaded + events_uploaded
  end

  # Initialize backfill tracking with a target timestamp
  # @param target [Time] the oldest timestamp to backfill to
  def initialize_backfill!(target:)
    return if backfill_target.present? # Already initialized

    update!(
      backfill_target: target,
      backfill_until: Time.current  # Start from now and work backwards
    )
  end

  # Get the next chunk window for backfill
  # @param chunk_hours [Integer] size of each chunk in hours
  # @return [Hash] { since:, until: } or nil if backfill complete
  def next_backfill_chunk(chunk_hours:)
    return nil if backfill_complete?

    chunk_end = backfill_until || Time.current
    chunk_start = chunk_end - chunk_hours.hours

    # Don't go past the target
    chunk_start = backfill_target if chunk_start < backfill_target

    { since: chunk_start.to_i, until: chunk_end.to_i }
  end

  # Mark a backfill chunk as completed
  # @param chunk_start [Time] the start of the completed chunk
  def mark_backfill_chunk_completed!(chunk_start:)
    update!(backfill_until: chunk_start)
  end

  # Check if backfill has reached the target
  def backfill_complete?
    return false unless backfill_target && backfill_until

    backfill_until <= backfill_target
  end

  # Progress percentage for backfill
  def backfill_progress_percent
    return 100 if backfill_complete?
    return 0 unless backfill_target && backfill_until

    total_duration = Time.current - backfill_target
    return 0 if total_duration <= 0 # Guard against division by zero

    completed_duration = Time.current - backfill_until
    ((completed_duration / total_duration) * 100).round(1)
  end
end
