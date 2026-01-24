# frozen_string_literal: true

# Uploads local events to a remote relay
class UploadEventsJob < ApplicationJob
  queue_as :uploads

  # @param relay_url [String] URL of the relay to upload to
  # @param record_ids [Array<Integer>, nil] database record IDs to upload (nil = all new events)
  def perform(relay_url:, record_ids: nil)
    result = Sync::UploadEvents.call(
      relay_url: relay_url,
      record_ids: record_ids
    )

    if result[:reason] == "no_events"
      Rails.logger.info "[UploadEventsJob] No events to upload to #{relay_url}"
    else
      Rails.logger.info "[UploadEventsJob] Upload complete to #{relay_url}: " \
                        "#{result[:published]} published, #{result[:duplicates]} duplicates, #{result[:failed]} failed"
    end
  rescue RelaySync::ConnectionError => e
    Rails.logger.error "[UploadEventsJob] #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[UploadEventsJob] Error: #{e.message}"
    raise
  end
end
