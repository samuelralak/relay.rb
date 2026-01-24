# frozen_string_literal: true

module Sync
  # Uploads local events to a remote relay
  class UploadEvents < BaseService
    include Connectionable
    include ErrorHandleable

    option :relay_url, type: Types::RelayUrl
    option :record_ids, type: Types::Array.of(Types::Integer).optional, default: -> { nil }

    def call
      with_error_handling do
        validate_connection!

        events = load_events
        return Success(published: 0, reason: "no_events") if events.empty?

        sync_state.mark_syncing!
        results = perform_upload(events)

        finalize_sync(results)
        Success(results)
      end
    end

    private

    def sync_state
      @sync_state ||= SyncState.find_or_create_by!(relay_url:, filter_hash: "upload") { |state|
        state.direction = "up"
      }
    end

    def load_events
      if record_ids.present?
        Event.where(id: record_ids).active.newest_first
      else
        sync_state.events_to_upload.limit(Constants::Batches::MAX_UPLOAD)
      end
    end

    def perform_upload(events)
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
