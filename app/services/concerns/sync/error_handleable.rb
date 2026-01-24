# frozen_string_literal: true

module Sync
  # Provides consistent error handling for sync services.
  # Include this in services that manage SyncState and need error tracking.
  module ErrorHandleable
    extend ActiveSupport::Concern

    private

    # Wraps a block with error handling that marks sync_state as errored.
    # @param manage_status [Boolean] Whether to manage sync_state status
    # @yield The block to execute
    # @return The result of the block
    def with_error_handling(manage_status: true)
      yield
    rescue StandardError => e
      handle_sync_error(e, manage_status:)
      raise
    end

    # Handles a sync error by logging and marking sync_state.
    # @param error [StandardError] The error that occurred
    # @param manage_status [Boolean] Whether to manage sync_state status
    def handle_sync_error(error, manage_status: true)
      Rails.logger.error "[#{self.class.name}] Error: #{error.message}"
      mark_sync_error!(error.message) if manage_status
    end

    # Marks the sync_state as errored with the given message.
    # Safe to call even if sync_state is nil.
    # @param message [String] The error message
    def mark_sync_error!(message)
      sync_state&.mark_error!(message)
    end
  end
end
