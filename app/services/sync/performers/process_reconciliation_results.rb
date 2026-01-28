# frozen_string_literal: true

module Sync
  module Performers
    # Processes Negentropy reconciliation results by downloading/uploading events.
    # Downloads events we need from the relay, and schedules uploads for events we have.
    class ProcessReconciliationResults < BaseService
      include Loggable

      option :connection, type: Types::Any
      option :relay_url, type: Types::RelayUrl
      option :have_ids, type: Types::Array.of(Types::String)
      option :need_ids, type: Types::Array.of(Types::String)
      option :direction, type: Types::Direction
      option :sync_state, type: Types::Any

      def call
        download_results = download_needed_events if should_download? && need_ids.any?
        schedule_uploads if should_upload? && have_ids.any?

        Success(
          downloaded: download_results&.[](:fetched) || 0,
          upload_scheduled: should_upload? && have_ids.any?
        )
      end

      private

      def download_needed_events
        logger.info "Fetching missing events", count: need_ids.size

        result = Actions::FetchEvents.call(
          connection:,
          event_ids: need_ids,
          batch_size:,
          sync_state:
        )

        logger.info "FetchEvents result", success: result.success?, value: result.success? ? result.value! : result.failure
        result.success? ? result.value! : { fetched: 0 }
      end

      def schedule_uploads
        events = Event.where(event_id: have_ids).active
        return unless events.any?

        Events::UploadJob.perform_later(
          relay_url:,
          record_ids: events.pluck(:id)
        )
      end

      def should_download?
        %w[down both].include?(direction)
      end

      def should_upload?
        %w[up both].include?(direction)
      end

      def batch_size
        RelaySync.configuration.sync_settings.batch_size
      end
    end
  end
end
