# frozen_string_literal: true

module Events
  class ProcessIncoming < BaseService
    include Dry::Monads[:result, :do]

    option :event_data, type: Types::Hash

    def call
      # Normalize keys to strings
      @data = event_data.transform_keys(&:to_s)

      # 1. Verify ID and signature
      yield Actions::VerifySignature.call(event_data: @data)

      # 2. Handle by kind (regular/replaceable/ephemeral/addressable)
      # Note: duplicate detection is handled by database unique constraint
      # in store services (returns Success(duplicate: true) on RecordNotUnique)
      result = yield handle_by_kind

      # 3. Check if this was a duplicate (store service caught RecordNotUnique)
      return Success(duplicate: true, event_id: @data["id"]) if result.is_a?(Hash) && result[:duplicate]

      # 4. Broadcast to subscribers (result is the saved Event)
      NostrRelay::Subscriptions.broadcast(result) if result

      # 5. NIP-50: Enqueue for search indexing if OpenSearch is enabled
      enqueue_search_indexing(result) if result.is_a?(Event)

      Success(event_id: @data["id"])
    end

    private

    # NIP-50: Enqueue event for search indexing
    def enqueue_search_indexing(event)
      return unless RelaySearch::Client.enabled?

      Search::IndexEventJob.perform_later(id: event.id)
    end

    def handle_by_kind
      kind = @data["kind"]

      if ::Events::Kinds.ephemeral?(kind)
        # Don't store, just broadcast in-memory
        NostrRelay::Subscriptions.broadcast_ephemeral(@data)
        Success(nil)
      elsif kind == ::Events::Kinds::DELETION
        # NIP-09: Handle deletion requests (stores event + enqueues deletion job)
        Actions::HandleDeletion.call(event_data: @data)
      elsif ::Events::Kinds.replaceable?(kind)
        Actions::StoreReplaceable.call(event_data: @data)
      elsif ::Events::Kinds.addressable?(kind)
        Actions::StoreAddressable.call(event_data: @data)
      else
        Actions::StoreRegular.call(event_data: @data)
      end
    end
  end
end
