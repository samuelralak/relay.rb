# frozen_string_literal: true

module SyncStates
  # Status and direction constants for SyncState model.
  module Statuses
    IDLE      = "idle"
    SYNCING   = "syncing"
    COMPLETED = "completed"
    ERROR     = "error"

    ALL = [ IDLE, SYNCING, COMPLETED, ERROR ].freeze
    ACTIVE = [ IDLE, SYNCING ].freeze

    # Direction constants for sync operations
    module Direction
      DOWN = "down"
      UP   = "up"
      BOTH = "both"

      ALL = [ DOWN, UP, BOTH ].freeze
      DOWNLOADS = [ DOWN, BOTH ].freeze
      UPLOADS = [ UP, BOTH ].freeze
    end
  end
end
