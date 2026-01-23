# frozen_string_literal: true

# Performs Negentropy (NIP-77) sync with a remote relay
class NegentropySyncJob < ApplicationJob
  queue_as :default

  # @param relay_url [String] URL of the relay to sync with
  # @param filter [Hash] Nostr filter for events to sync
  # @param direction [String] sync direction (down, up, both)
  def perform(relay_url:, filter: {}, direction: "down")
    @relay_url = relay_url
    @filter = filter.symbolize_keys
    @direction = direction
    @sync_state = find_sync_state

    connection = RelaySync.manager.connection_for(relay_url)
    unless connection&.connected?
      Rails.logger.error "[NegentropySyncJob] Not connected to #{relay_url}"
      @sync_state&.mark_error!("Not connected to relay")
      return
    end

    Rails.logger.info "[NegentropySyncJob] Starting Negentropy sync with #{relay_url}"

    perform_sync(connection)
  rescue StandardError => e
    Rails.logger.error "[NegentropySyncJob] Error: #{e.message}"
    @sync_state&.mark_error!(e.message)
    raise
  end

  private

  def find_sync_state
    filter_hash = Digest::SHA256.hexdigest(@filter.to_json)[0, 16]
    SyncState.find_by(relay_url: @relay_url, filter_hash: filter_hash)
  end

  def perform_sync(connection)
    # Build local storage with matching events
    storage = build_local_storage

    # Create reconciler
    reconciler = Negentropy::ClientReconciler.new(storage: storage)

    # Generate initial message
    initial_message = reconciler.initiate

    # Generate unique subscription ID
    subscription_id = "neg_#{SecureRandom.hex(8)}"

    # Send NEG-OPEN
    connection.neg_open(subscription_id, @filter, initial_message)

    # Process responses (simplified - in production, this would use callbacks)
    total_downloaded = 0
    total_uploaded = 0

    # Note: In a real implementation, this would be callback-driven
    # For now, we log the sync initiation
    Rails.logger.info "[NegentropySyncJob] Sent NEG-OPEN for #{subscription_id}"
    Rails.logger.info "[NegentropySyncJob] Local storage has #{storage.size} events"

    # The actual message handling happens via callbacks in the Connection class
    # The sync completes when we receive an empty response from reconcile()
  end

  def build_local_storage
    scope = Event.active

    # Apply filter criteria
    scope = scope.where(kind: @filter[:kinds]) if @filter[:kinds].present?
    scope = scope.where("nostr_created_at >= ?", Time.at(@filter[:since]).utc) if @filter[:since].present?
    scope = scope.where("nostr_created_at <= ?", Time.at(@filter[:until]).utc) if @filter[:until].present?
    scope = scope.where(pubkey: @filter[:authors]) if @filter[:authors].present?

    Negentropy::Storage.from_scope(scope)
  end

  def should_download?
    @direction.in?(%w[down both])
  end

  def should_upload?
    @direction.in?(%w[up both])
  end
end
