# frozen_string_literal: true

module SyncStates
  # Handles filter building and sync resumption logic.
  module Resumable
    extend ActiveSupport::Concern

    def download_filter(base_filter = {})
      filter = base_filter.dup
      filter[:since] = last_download_timestamp.to_i if last_download_timestamp
      filter
    end

    # Returns a filter for resuming sync with overlap to prevent gaps.
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

    # Check if this sync has made progress and can be resumed.
    def resumable?
      last_download_timestamp.present? || last_upload_timestamp.present?
    end

    def events_to_upload
      scope = Event.active.newest_first
      scope = scope.where("nostr_created_at > ?", last_upload_timestamp) if last_upload_timestamp
      scope
    end

    def download_enabled?
      direction.in?(SyncStates::Statuses::Direction::DOWNLOADS)
    end

    def upload_enabled?
      direction.in?(SyncStates::Statuses::Direction::UPLOADS)
    end
  end
end
