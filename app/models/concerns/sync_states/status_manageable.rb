# frozen_string_literal: true

module SyncStates
  # Handles status transitions and state queries.
  module StatusManageable
    extend ActiveSupport::Concern

    # Status transition methods

    def mark_syncing!
      update!(status: SyncStates::Statuses::SYNCING, error_message: nil)
    end

    def mark_completed!
      update!(status: SyncStates::Statuses::COMPLETED, error_message: nil)
    end

    def mark_error!(message)
      update!(status: SyncStates::Statuses::ERROR, error_message: message)
    end

    def reset_to_idle!
      update!(status: SyncStates::Statuses::IDLE, error_message: nil)
    end

    # Status query methods

    def idle?
      status == SyncStates::Statuses::IDLE
    end

    def syncing?
      status == SyncStates::Statuses::SYNCING
    end

    def error?
      status == SyncStates::Statuses::ERROR
    end

    def completed?
      status == SyncStates::Statuses::COMPLETED
    end

    # Check if sync was interrupted (marked syncing but no recent activity)
    def stale?(threshold: 5.minutes)
      syncing? && updated_at < threshold.ago
    end
  end
end
