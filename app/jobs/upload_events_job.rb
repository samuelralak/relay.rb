# frozen_string_literal: true

# Uploads local events to a remote relay
class UploadEventsJob < ApplicationJob
  queue_as :low_priority

  # @param relay_url [String] URL of the relay to upload to
  # @param record_ids [Array<Integer>, nil] database record IDs to upload (nil = all new events)
  def perform(relay_url:, record_ids: nil)
    @relay_url = relay_url
    @sync_state = find_or_create_sync_state

    connection = RelaySync.manager.connection_for(relay_url)
    unless connection&.connected?
      Rails.logger.error "[UploadEventsJob] Not connected to #{relay_url}"
      @sync_state&.mark_error!("Not connected to relay")
      return
    end

    events = load_events(record_ids)

    if events.empty?
      Rails.logger.info "[UploadEventsJob] No events to upload to #{relay_url}"
      @sync_state.mark_completed!
      return
    end

    Rails.logger.info "[UploadEventsJob] Uploading #{events.count} events to #{relay_url}"

    @sync_state.mark_syncing!

    upload_events(connection, events)
  rescue StandardError => e
    Rails.logger.error "[UploadEventsJob] Error: #{e.message}"
    @sync_state&.mark_error!(e.message)
    raise
  end

  private

  def find_or_create_sync_state
    SyncState.find_or_create_by!(relay_url: @relay_url, filter_hash: "upload") do |state|
      state.direction = "up"
    end
  end

  def load_events(record_ids)
    if record_ids.present?
      Event.where(id: record_ids).active.newest_first
    else
      @sync_state.events_to_upload.limit(1000)
    end
  end

  def upload_events(connection, events)
    config = RelaySync.configuration.sync_settings
    publisher = RelaySync::EventPublisher.new(connection)

    results = publisher.publish_batch(
      events,
      batch_size: config.upload_batch_size,
      delay: config.upload_delay
    ) do |event, result|
      if result[:success] || result[:message]&.include?("duplicate")
        @sync_state.mark_upload_progress!(
          event_id: event.event_id,
          timestamp: event.nostr_created_at
        )
      end
    end

    Rails.logger.info "[UploadEventsJob] Upload complete: #{results[:published]} published, " \
                      "#{results[:duplicates]} duplicates, #{results[:failed]} failed"

    if results[:failed].zero?
      @sync_state.mark_completed!
    else
      @sync_state.mark_error!("#{results[:failed]} events failed to upload")
    end
  end
end
