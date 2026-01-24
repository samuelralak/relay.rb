# frozen_string_literal: true

module SyncStates
  # Class methods for finding and creating SyncState records.
  # Included via `extend` to make these class methods.
  module Finder
    # Compute a stable filter_hash for a given direction and filter.
    # This ensures one SyncState per relay+direction+filter combination.
    # @param direction [String] "down", "up", or "both"
    # @param filter [Hash] optional filter criteria (kinds, authors, etc.)
    # @return [String] 16-character hex hash
    def compute_filter_hash(direction:, filter: {})
      stable_filter = filter.except(:since, :until).symbolize_keys
      sorted_filter = stable_filter.sort.to_h
      Digest::SHA256.hexdigest("#{direction}:#{sorted_filter.to_json}")[0, 16]
    end

    # Find or create a SyncState for the given relay and parameters.
    # @param relay_url [String] the relay URL
    # @param direction [String] "down", "up", or "both"
    # @param filter [Hash] optional filter criteria
    # @return [SyncState]
    def for_sync(relay_url:, direction:, filter: {})
      filter_hash = compute_filter_hash(direction:, filter:)

      find_or_create_by!(relay_url:, filter_hash:) do |state|
        state.direction = direction
        state.status = Statuses::IDLE
        state.events_downloaded = 0
        state.events_uploaded = 0
      end
    rescue ActiveRecord::RecordNotUnique
      # Handle race condition: another process created the record simultaneously
      find_by!(relay_url:, filter_hash:)
    end
  end
end
