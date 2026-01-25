# frozen_string_literal: true

module Events
  class ProcessIncoming < BaseService
    include Dry::Monads[:result, :do]

    option :event_data, type: Types::Hash

    def call
      # Normalize keys to strings
      @data = event_data.transform_keys(&:to_s)

      # 1. Verify ID and signature
      yield VerifySignature.call(event_data: @data)

      # 2. Handle by kind (regular/replaceable/ephemeral/addressable)
      # Note: duplicate detection is handled by database unique constraint
      # in store services (returns Success(duplicate: true) on RecordNotUnique)
      result = yield handle_by_kind

      # 3. Check if this was a duplicate (store service caught RecordNotUnique)
      return Success(duplicate: true, event_id: @data["id"]) if result.is_a?(Hash) && result[:duplicate]

      # 4. Broadcast to subscribers (result is the saved Event)
      NostrRelay::Subscriptions.broadcast(result) if result
      Success(event_id: @data["id"])
    end

    private

    def handle_by_kind
      kind = @data["kind"]

      if ::Events::Kinds.ephemeral?(kind)
        # Don't store, just broadcast in-memory
        NostrRelay::Subscriptions.broadcast_ephemeral(@data)
        Success(nil)
      elsif ::Events::Kinds.replaceable?(kind)
        StoreReplaceable.call(event_data: @data)
      elsif ::Events::Kinds.addressable?(kind)
        StoreAddressable.call(event_data: @data)
      else
        StoreRegular.call(event_data: @data)
      end
    end
  end
end
