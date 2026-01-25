# frozen_string_literal: true

module Events
  module Actions
    # NIP-09: Handles deletion request events (kind 5).
    # Stores the deletion event synchronously, then enqueues a background job
    # to process the actual deletions asynchronously.
    class HandleDeletion < BaseService
      include Dry::Monads[:result]

      option :event_data, type: Types::Hash

      def call
        # 1. Store the deletion event itself (must persist per NIP-09)
        store_result = StoreRegular.call(event_data:)

        case store_result
        in Success(duplicate: true)
          # Already processed via RecordNotUnique
          Success(duplicate: true, event_id: event_data["id"])
        in Success(event)
          # New event stored, enqueue processing
          ProcessDeletionJob.perform_later(event.id)
          Success(event)
        in Failure[ :invalid, message ] if message.include?("has already been taken")
          # Duplicate caught by model validation
          Success(duplicate: true, event_id: event_data["id"])
        in Failure => failure
          # Other failure, propagate
          failure
        end
      end
    end
  end
end
