# frozen_string_literal: true

module Sync
  # Uploads local events to a remote relay
  class UploadEvents < BaseService
    option :relay_url, type: Types::RelayUrl
    option :record_ids, type: Types::Array.of(Types::Integer).optional, default: -> { nil }

    def call
      validate_connection!

      events = load_events
      return { uploaded: 0, reason: "no_events" } if events.empty?

      sync_state.mark_syncing!
      results = upload_events(events)

      finalize_sync(results)
      results
    rescue StandardError => e
      sync_state&.mark_error!(e.message)
      raise
    end

    private

    def validate_connection!
      raise RelaySync::ConnectionError, "Not connected to #{relay_url}" unless connection&.connected?
    end

    def connection
      @connection ||= RelaySync.manager.connection_for(relay_url)
    end

    def sync_state
      @sync_state ||= SyncState.find_or_create_by!(relay_url: relay_url, filter_hash: "upload") do |state|
        state.direction = "up"
      end
    end

    def load_events
      if record_ids.present?
        Event.where(id: record_ids).active.newest_first
      else
        sync_state.events_to_upload.limit(1000)
      end
    end

    def upload_events(events)
      config = RelaySync.configuration.sync_settings
      publisher = RelaySync::EventPublisher.new(connection)

      publisher.publish_batch(
        events,
        batch_size: config.upload_batch_size,
        delay: config.upload_delay
      ) do |event, result|
        if result[:success] || result[:message]&.include?("duplicate")
          sync_state.mark_upload_progress!(
            event_id: event.event_id,
            timestamp: event.nostr_created_at
          )
        end
      end
    end

    def finalize_sync(results)
      if results[:failed].zero?
        sync_state.mark_completed!
      else
        sync_state.mark_error!("#{results[:failed]} events failed to upload")
      end
    end
  end
end
