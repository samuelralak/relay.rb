# frozen_string_literal: true

module Sync
  module Actions
    # Fetches events from a relay by their IDs in batches.
    # Queues Events::ProcessJob for each received event.
    class FetchEvents < BaseService
      include Loggable
      include TimeoutWaitable

      option :connection, type: Types::Any
      option :event_ids, type: Types::Array.of(Types::String)
      option :batch_size, type: Types::Integer, default: -> { Constants::Batches::DEFAULT_FETCH }
      option :sync_state, type: Types::Any.optional, default: -> { nil }

      def call
        return Success(fetched: 0, batches: 0, complete: true) if event_ids.empty?

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

        Success(fetched: @fetched_count, batches: batch_count, complete: all_complete)
      end

      private

      def fetch_batch(batch)
        sub_id = "#{Constants::SubscriptionPrefixes::FETCH}#{SecureRandom.hex(Constants::IdLengths::FETCH_ID)}"
        filter = { ids: batch }

        tracker = create_sync_tracker
        batch_fetched = 0
        batch_mutex = Mutex.new

        # Register event handler to process and count received events
        RelaySync.manager.register_event_handler(sub_id) do |conn, _subscription_id, event_data|
          @counter_mutex.synchronize do @fetched_count += 1 end
          batch_mutex.synchronize do batch_fetched += 1 end
          # Queue event for processing
          Events::ProcessJob.perform_later(event_data.to_json, conn.url)
        end

        RelaySync.manager.register_eose_handler(sub_id) do
          tracker.mark_complete!
        end

        begin
          connection.subscribe(sub_id, [ filter ])

          completed = wait_with_timeout(
            timeout: Constants::Timeouts::FETCH_BATCH,
            tracker:
          ) { tracker.complete_unlocked? }

          unless completed
            logger.warn "EOSE timeout for batch fetch", subscription_id: sub_id
          end

          final_batch_count = batch_mutex.synchronize { batch_fetched }
          [ completed, final_batch_count ]
        ensure
          RelaySync.manager.unregister_event_handler(sub_id)
          RelaySync.manager.unregister_eose_handler(sub_id)
          connection.unsubscribe(sub_id)
        end
      end
    end
  end
end
