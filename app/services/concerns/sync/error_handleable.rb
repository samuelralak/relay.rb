# frozen_string_literal: true

module Sync
  # Provides consistent error handling for sync services.
  module ErrorHandleable
    extend ActiveSupport::Concern

    private

    def with_error_handling(manage_status: true)
      yield
    rescue StandardError => e
      handle_sync_error(e, manage_status:)
      raise
    end

    def handle_sync_error(error, manage_status: true)
      Rails.logger.error "[#{self.class.name}] Error: #{error.message}"
      mark_sync_error!(error.message) if manage_status
    end

    def mark_sync_error!(message)
      sync_state&.mark_error!(message)
    end
  end
end
