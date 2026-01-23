# frozen_string_literal: true

class SyncState < ApplicationRecord
  STATUSES = %w[idle syncing completed error].freeze
  DIRECTIONS = %w[down up both].freeze

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
    update!(
      last_download_event_id: event_id,
      last_download_timestamp: timestamp,
      last_synced_at: Time.current,
      events_downloaded: events_downloaded + count
    )
  end

  def mark_upload_progress!(event_id:, timestamp:, count: 1)
    update!(
      last_upload_event_id: event_id,
      last_upload_timestamp: timestamp,
      last_synced_at: Time.current,
      events_uploaded: events_uploaded + count
    )
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

  def download_filter(base_filter = {})
    filter = base_filter.dup
    filter[:since] = last_download_timestamp.to_i if last_download_timestamp
    filter
  end

  def events_to_upload
    scope = Event.active.newest_first
    scope = scope.where("nostr_created_at > ?", last_upload_timestamp) if last_upload_timestamp
    scope
  end

  def total_events_synced
    events_downloaded + events_uploaded
  end
end
