# frozen_string_literal: true

# Tracks sync progress for a relay+filter combination.
# See concerns for detailed behavior documentation.
class SyncState < ApplicationRecord
  # Class methods (via extend)
  extend SyncStates::Finder

  # Instance methods (via include)
  include SyncStates::StatusManageable
  include SyncStates::ProgressTrackable
  include SyncStates::BackfillTrackable
  include SyncStates::Resumable

  # Validations
  validates :relay_url, presence: true, uniqueness: { scope: :filter_hash }
  validates :status, presence: true, inclusion: { in: SyncStates::Statuses::ALL }
  validates :direction, presence: true, inclusion: { in: SyncStates::Statuses::Direction::ALL }
  validates :events_downloaded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :events_uploaded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes
  scope :for_relay, ->(url) { where(relay_url: url) }
  scope :active, -> { where(status: SyncStates::Statuses::ACTIVE) }
  scope :needs_sync, -> { where(status: SyncStates::Statuses::IDLE) }
  scope :syncing, -> { where(status: SyncStates::Statuses::SYNCING) }
  scope :completed, -> { where(status: SyncStates::Statuses::COMPLETED) }
  scope :errored, -> { where(status: SyncStates::Statuses::ERROR) }
  scope :downloads, -> { where(direction: SyncStates::Statuses::Direction::DOWNLOADS) }
  scope :uploads, -> { where(direction: SyncStates::Statuses::Direction::UPLOADS) }
end
