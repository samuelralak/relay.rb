# frozen_string_literal: true

# Starts a streaming subscription to receive real-time events from a relay
class StreamingSyncJob < ApplicationJob
  queue_as :default

  # @param relay_url [String] URL of the relay to stream from
  # @param filter [Hash] Nostr filter for events to receive
  def perform(relay_url:, filter: {})
    @relay_url = relay_url
    @filter = filter.symbolize_keys
    @sync_state = find_or_create_sync_state

    connection = RelaySync.manager.connection_for(relay_url)
    unless connection&.connected?
      Rails.logger.error "[StreamingSyncJob] Not connected to #{relay_url}"
      @sync_state&.mark_error!("Not connected to relay")
      return
    end

    Rails.logger.info "[StreamingSyncJob] Starting streaming sync with #{relay_url}"

    # Generate unique subscription ID
    subscription_id = "stream_#{SecureRandom.hex(8)}"

    # Build filter with since from sync state
    effective_filter = build_filter

    # Subscribe to the relay
    connection.subscribe(subscription_id, [effective_filter])

    @sync_state.mark_syncing!

    Rails.logger.info "[StreamingSyncJob] Subscribed with filter: #{effective_filter}"
  rescue StandardError => e
    Rails.logger.error "[StreamingSyncJob] Error: #{e.message}"
    @sync_state&.mark_error!(e.message)
    raise
  end

  private

  def find_or_create_sync_state
    filter_hash = Digest::SHA256.hexdigest(@filter.to_json)[0, 16]

    SyncState.find_or_create_by!(relay_url: @relay_url, filter_hash: filter_hash) do |state|
      state.direction = "down"
    end
  end

  def build_filter
    filter = @filter.dup

    # Use last download timestamp if available
    if @sync_state.last_download_timestamp
      filter[:since] = @sync_state.last_download_timestamp.to_i
    elsif filter[:since].nil?
      # Default to current time for new subscriptions
      filter[:since] = Time.current.to_i
    end

    # Ensure we have kinds if not specified
    filter[:kinds] ||= RelaySync.configuration.sync_settings.event_kinds

    filter
  end
end
