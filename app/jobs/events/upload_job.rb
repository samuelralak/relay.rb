# frozen_string_literal: true

module Events
  # Uploads local events to a remote relay
  class UploadJob < ApplicationJob
    include JobLoggable

    queue_as :uploads

    # @param relay_url [String] URL of the relay to upload to
    # @param record_ids [Array<Integer>, nil] database record IDs to upload (nil = all new events)
    def perform(relay_url:, record_ids: nil)
      result = ::Sync::UploadEvents.call(
        relay_url:,
        record_ids:
      )
      values = result.value!

      if values[:reason] == "no_events"
        logger.info("No events to upload", relay_url:)
      else
        logger.info "Upload complete",
          relay_url:,
          published: values[:published],
          duplicates: values[:duplicates],
          failed: values[:failed]
      end
    rescue RelaySync::ConnectionError => e
      logger.error "Connection error", error: e.message
    rescue StandardError => e
      logger.error "Error", error: e.message
      raise
    end
  end
end
