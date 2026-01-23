# frozen_string_literal: true

require "singleton"

module RelaySync
  # Manages relay connections and coordinates sync operations
  class Manager
    include Singleton

    attr_reader :connections

    def initialize
      @connections = {}
      @mutex = Mutex.new
    end

    # Start the sync manager and connect to all enabled relays
    def start
      Rails.logger.info "[RelaySync::Manager] Starting sync manager"

      RelaySync.configuration.enabled_relays.each do |relay_config|
        add_connection(relay_config)
      end
    end

    # Stop all connections
    def stop
      Rails.logger.info "[RelaySync::Manager] Stopping sync manager"

      @mutex.synchronize do
        @connections.values.each(&:disconnect)
        @connections.clear
      end
    end

    # Get or create a connection to a relay
    # @param url [String] relay URL
    # @return [Connection] relay connection
    def connection_for(url)
      @mutex.synchronize do
        @connections[url]
      end
    end

    # Start Negentropy sync with a relay
    # @param relay_url [String] relay URL
    # @param filter [Hash] Nostr filter for events to sync
    # @param direction [String] sync direction (down, up, both)
    def start_negentropy_sync(relay_url, filter: {}, direction: "down")
      connection = connection_for(relay_url)
      return unless connection&.connected?

      sync_state = find_or_create_sync_state(relay_url, filter, direction)
      sync_state.mark_syncing!

      NegentropySyncJob.perform_later(
        relay_url: relay_url,
        filter: sync_state.download_filter(filter),
        direction: direction
      )
    end

    # Start streaming sync with a relay
    # @param relay_url [String] relay URL
    # @param filter [Hash] Nostr filter
    def start_streaming_sync(relay_url, filter: {})
      connection = connection_for(relay_url)
      return unless connection&.connected?

      sync_state = find_or_create_sync_state(relay_url, filter, "down")

      StreamingSyncJob.perform_later(
        relay_url: relay_url,
        filter: sync_state.download_filter(filter)
      )
    end

    # Upload events to a relay
    # @param relay_url [String] relay URL
    # @param events [Array<Event>] events to upload (optional, defaults to all new events)
    def upload_events(relay_url, events: nil)
      connection = connection_for(relay_url)
      return unless connection&.connected?

      sync_state = find_or_create_sync_state(relay_url, {}, "up")

      UploadEventsJob.perform_later(
        relay_url: relay_url,
        event_ids: events&.map(&:id)
      )
    end

    # Start backfill sync for all configured relays
    # @param since [Integer] Unix timestamp to sync from
    def start_backfill(since: nil)
      since ||= RelaySync.configuration.sync_settings.backfill_since.ago.to_i

      RelaySync.configuration.backfill_relays.each do |relay_config|
        filter = {
          kinds: RelaySync.configuration.sync_settings.event_kinds,
          since: since
        }

        if relay_config.negentropy?
          start_negentropy_sync(relay_config.url, filter: filter, direction: relay_config.direction)
        else
          start_streaming_sync(relay_config.url, filter: filter)
        end
      end
    end

    # Start streaming from all configured relays
    def start_streaming
      RelaySync.configuration.download_relays.each do |relay_config|
        filter = {
          kinds: RelaySync.configuration.sync_settings.event_kinds,
          since: Time.current.to_i
        }

        start_streaming_sync(relay_config.url, filter: filter)
      end
    end

    # Get status of all connections
    # @return [Hash] status information
    def status
      @mutex.synchronize do
        {
          connections: @connections.transform_values do |conn|
            {
              state: conn.state,
              subscriptions: conn.subscriptions.keys,
              reconnect_attempts: conn.reconnect_attempts
            }
          end,
          sync_states: SyncState.all.map do |state|
            {
              relay_url: state.relay_url,
              direction: state.direction,
              status: state.status,
              events_downloaded: state.events_downloaded,
              events_uploaded: state.events_uploaded,
              last_synced_at: state.last_synced_at
            }
          end
        }
      end
    end

    private

    def add_connection(relay_config)
      callbacks = {
        on_connect: ->(conn) { handle_connect(conn) },
        on_disconnect: ->(conn, code, reason) { handle_disconnect(conn, code, reason) },
        on_event: ->(conn, sub_id, event) { handle_event(conn, sub_id, event) },
        on_eose: ->(conn, sub_id) { handle_eose(conn, sub_id) },
        on_ok: ->(conn, event_id, success, message) { handle_ok(conn, event_id, success, message) },
        on_error: ->(conn, message) { handle_error(conn, message) },
        on_neg_msg: ->(conn, sub_id, message) { handle_neg_msg(conn, sub_id, message) },
        on_neg_err: ->(conn, sub_id, error) { handle_neg_err(conn, sub_id, error) }
      }

      connection = Connection.new(url: relay_config.url, callbacks: callbacks)

      @mutex.synchronize do
        @connections[relay_config.url] = connection
      end

      connection.connect
    end

    def find_or_create_sync_state(relay_url, filter, direction)
      filter_hash = Digest::SHA256.hexdigest(filter.to_json)[0, 16]

      SyncState.find_or_create_by!(relay_url: relay_url, filter_hash: filter_hash) do |state|
        state.direction = direction
      end
    end

    # Connection callbacks

    def handle_connect(connection)
      Rails.logger.info "[RelaySync::Manager] Connected to #{connection.url}"
    end

    def handle_disconnect(connection, code, reason)
      Rails.logger.info "[RelaySync::Manager] Disconnected from #{connection.url}: #{code} - #{reason}"
    end

    def handle_event(connection, subscription_id, event_data)
      ProcessEventJob.perform_later(event_data.to_json, connection.url)
    end

    def handle_eose(connection, subscription_id)
      Rails.logger.debug "[RelaySync::Manager] EOSE for #{subscription_id} from #{connection.url}"
    end

    def handle_ok(connection, event_id, success, message)
      Rails.logger.debug "[RelaySync::Manager] OK for #{event_id}: #{success} - #{message}"
    end

    def handle_error(connection, message)
      Rails.logger.error "[RelaySync::Manager] Error from #{connection.url}: #{message}"
    end

    def handle_neg_msg(connection, subscription_id, message)
      # Negentropy messages are handled by the sync job
      Rails.logger.debug "[RelaySync::Manager] NEG-MSG for #{subscription_id} from #{connection.url}"
    end

    def handle_neg_err(connection, subscription_id, error)
      Rails.logger.error "[RelaySync::Manager] NEG-ERR for #{subscription_id} from #{connection.url}: #{error}"
    end
  end
end
