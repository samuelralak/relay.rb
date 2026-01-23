# frozen_string_literal: true

# Performs Negentropy (NIP-77) sync with a remote relay
class NegentropySyncJob < ApplicationJob
  queue_as :default

  SYNC_TIMEOUT = 60 # seconds
  FETCH_TIMEOUT = 10 # seconds per batch

  # @param relay_url [String] URL of the relay to sync with
  # @param filter [Hash] Nostr filter for events to sync
  # @param direction [String] sync direction (down, up, both)
  def perform(relay_url:, filter: {}, direction: "down")
    @relay_url = relay_url
    @filter = filter.symbolize_keys
    @direction = direction
    @sync_state = find_or_create_sync_state
    @have_ids = []
    @need_ids = []
    @mutex = Mutex.new
    @condition = ConditionVariable.new
    @complete = false

    connection = RelaySync.manager.connection_for(relay_url)
    unless connection&.connected?
      Rails.logger.error "[NegentropySyncJob] Not connected to #{relay_url}"
      @sync_state&.mark_error!("Not connected to relay")
      return
    end

    Rails.logger.info "[NegentropySyncJob] Starting Negentropy sync with #{relay_url} (direction: #{direction})"
    @sync_state.mark_syncing!

    perform_sync(connection)
  rescue StandardError => e
    Rails.logger.error "[NegentropySyncJob] Error: #{e.message}"
    @sync_state&.mark_error!(e.message)
    raise
  end

  private

  def find_or_create_sync_state
    filter_hash = Digest::SHA256.hexdigest(@filter.except(:since, :until).to_json)[0, 16]
    SyncState.find_or_create_by!(relay_url: @relay_url, filter_hash: filter_hash) do |state|
      state.direction = @direction
    end
  end

  def perform_sync(connection)
    # Build local storage with matching events
    storage = build_local_storage
    Rails.logger.info "[NegentropySyncJob] Local storage has #{storage.size} events"

    # Create reconciler
    frame_size = RelaySync.configuration.sync_settings.negentropy_frame_size
    reconciler = Negentropy::ClientReconciler.new(storage: storage, frame_size_limit: frame_size)

    # Generate unique subscription ID
    subscription_id = "neg_#{SecureRandom.hex(8)}"

    # Register handler for NEG-MSG responses
    RelaySync.manager.register_neg_handler(subscription_id, reconciler: reconciler) do |have_ids, need_ids, complete|
      handle_reconcile_result(have_ids, need_ids, complete, connection)
    end

    begin
      # Generate and send initial message
      initial_message = reconciler.initiate
      connection.neg_open(subscription_id, @filter, initial_message)
      Rails.logger.info "[NegentropySyncJob] Sent NEG-OPEN for #{subscription_id}"

      # Wait for reconciliation to complete - timeout is a hard failure
      completed = wait_for_completion
      unless completed
        Rails.logger.error "[NegentropySyncJob] Sync timeout - aborting without processing partial results"
        connection.neg_close(subscription_id)
        @sync_state.mark_error!("Sync timeout after #{SYNC_TIMEOUT}s")
        return
      end

      # Process results only if reconciliation completed successfully
      process_sync_results(connection)

      @sync_state.mark_completed!
      Rails.logger.info "[NegentropySyncJob] Sync complete. Have: #{@have_ids.size}, Need: #{@need_ids.size}"
    ensure
      RelaySync.manager.unregister_neg_handler(subscription_id)
    end
  end

  def handle_reconcile_result(have_ids, need_ids, complete, connection)
    @mutex.synchronize do
      @have_ids.concat(have_ids)
      @need_ids.concat(need_ids)

      if complete
        @complete = true
        @condition.broadcast
      end
    end
  end

  # Wait for reconciliation to complete
  # @return [Boolean] true if completed, false if timeout
  def wait_for_completion
    deadline = Time.current + SYNC_TIMEOUT

    @mutex.synchronize do
      until @complete
        remaining = deadline - Time.current
        return false if remaining <= 0

        @condition.wait(@mutex, remaining)
      end
      true
    end
  end

  def process_sync_results(connection)
    # Download events we need (if direction allows)
    if should_download? && @need_ids.any?
      Rails.logger.info "[NegentropySyncJob] Requesting #{@need_ids.size} missing events"
      fetch_missing_events(connection, @need_ids)
    end

    # Upload events we have that remote needs (if direction allows)
    if should_upload? && @have_ids.any?
      Rails.logger.info "[NegentropySyncJob] Uploading #{@have_ids.size} events to relay"
      upload_events(@have_ids)
    end
  end

  def fetch_missing_events(connection, event_ids)
    # Request missing events in batches with EOSE-aware completion
    batch_size = RelaySync.configuration.sync_settings.batch_size
    fetched_count = 0

    event_ids.each_slice(batch_size) do |batch|
      sub_id = "fetch_#{SecureRandom.hex(4)}"
      filter = { ids: batch }

      # Set up EOSE waiting mechanism
      eose_mutex = Mutex.new
      eose_condition = ConditionVariable.new
      eose_received = false

      RelaySync.manager.register_eose_handler(sub_id) do
        eose_mutex.synchronize do
          eose_received = true
          eose_condition.broadcast
        end
      end

      begin
        connection.subscribe(sub_id, [filter])

        # Wait for EOSE or timeout
        deadline = Time.current + FETCH_TIMEOUT
        eose_mutex.synchronize do
          until eose_received
            remaining = deadline - Time.current
            if remaining <= 0
              Rails.logger.warn "[NegentropySyncJob] EOSE timeout for batch fetch #{sub_id}"
              break
            end
            eose_condition.wait(eose_mutex, remaining)
          end
        end

        fetched_count += batch.size
      ensure
        RelaySync.manager.unregister_eose_handler(sub_id)
        connection.unsubscribe(sub_id)
      end
    end

    @sync_state.update!(events_downloaded: @sync_state.events_downloaded + fetched_count)
  end

  # Upload events that we have but remote needs
  # @param nostr_event_ids [Array<String>] hex-encoded Nostr event IDs
  def upload_events(nostr_event_ids)
    events = Event.where(event_id: nostr_event_ids).active
    return if events.empty?

    UploadEventsJob.perform_later(
      relay_url: @relay_url,
      record_ids: events.pluck(:id)
    )
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
