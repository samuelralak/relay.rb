# frozen_string_literal: true

module Events
  # Uploads local events to a remote relay
  class UploadJob < ApplicationJob
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
        Rails.logger.info "[Events::UploadJob] No events to upload to #{relay_url}"
      else
        Rails.logger.info "[Events::UploadJob] Upload complete to #{relay_url}: " \
                          "#{values[:published]} published, #{values[:duplicates]} duplicates, #{values[:failed]} failed"
      end
    rescue RelaySync::ConnectionError => e
      Rails.logger.error "[Events::UploadJob] #{e.message}"
    rescue StandardError => e
      Rails.logger.error "[Events::UploadJob] Error: #{e.message}"
      raise
    end
  end
end
