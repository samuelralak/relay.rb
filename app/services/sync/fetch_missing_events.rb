# frozen_string_literal: true

module Sync
  # Fetches missing events from a relay by their IDs
  class FetchMissingEvents < BaseService
    FETCH_TIMEOUT = 10 # seconds per batch

    option :connection, type: Types::Any
    option :event_ids, type: Types::Array.of(Types::String)
    option :batch_size, type: Types::Integer, default: -> { 100 }
    option :sync_state, type: Types::Any.optional, default: -> { nil }

    def call
      return { fetched: 0, batches: 0, complete: true } if event_ids.empty?

      @fetched_count = 0
      @counter_mutex = Mutex.new
      batch_count = 0
      all_complete = true

      event_ids.each_slice(batch_size) do |batch|
        batch_complete, batch_fetched = fetch_batch(batch)
        all_complete = false unless batch_complete
        batch_count += 1

        # Incrementally update SyncState after each batch for robustness
        # This ensures counts persist even if connection drops mid-sync
        if sync_state && batch_fetched > 0
          sync_state.increment_events_downloaded!(batch_fetched)
        end
      end

      { fetched: @fetched_count, batches: batch_count, complete: all_complete }
    end

    private

    def fetch_batch(batch)
      sub_id = "fetch_#{SecureRandom.hex(4)}"
      filter = { ids: batch }

      state = { eose_received: false }
      mutex = Mutex.new
      condition = ConditionVariable.new
      batch_fetched = 0
      batch_mutex = Mutex.new

      # Register event handler to process and count received events
      RelaySync.manager.register_event_handler(sub_id) do |conn, subscription_id, event_data|
        @counter_mutex.synchronize { @fetched_count += 1 }
        batch_mutex.synchronize { batch_fetched += 1 }
        # Queue event for processing
        ProcessEventJob.perform_later(event_data.to_json, conn.url)
      end

      RelaySync.manager.register_eose_handler(sub_id) do
        mutex.synchronize do
          state[:eose_received] = true
          condition.broadcast
        end
      end

      begin
        connection.subscribe(sub_id, [ filter ])
        wait_for_eose(mutex, condition, state, sub_id)
        final_batch_count = batch_mutex.synchronize { batch_fetched }
        [ state[:eose_received], final_batch_count ]
      ensure
        RelaySync.manager.unregister_event_handler(sub_id)
        RelaySync.manager.unregister_eose_handler(sub_id)
        connection.unsubscribe(sub_id)
      end
    end

    def wait_for_eose(mutex, condition, state, sub_id)
      deadline = Time.now + FETCH_TIMEOUT

      mutex.synchronize do
        until state[:eose_received]
          remaining = deadline - Time.now
          if remaining <= 0
            Rails.logger.warn "[Sync::FetchMissingEvents] EOSE timeout for batch fetch #{sub_id}"
            break
          end
          condition.wait(mutex, remaining)
        end
      end
    end
  end
end
