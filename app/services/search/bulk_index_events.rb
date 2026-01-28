# frozen_string_literal: true

module Search
  class BulkIndexEvents < BaseService
    include Loggable

    option :batch_size, type: Types::Integer, default: -> { 1000 }
    option :scope, type: Types::Any, default: -> { Event.all }

    # Note: Returns Failure when search disabled (vs IndexEvent which returns Success)
    # This is intentional: bulk indexing is explicit user action, should fail visibly
    def call
      return Failure(:search_disabled) unless RelaySearch::Client.available?

      indexed = 0
      errors = []

      scope.find_in_batches(batch_size:) do |batch|
        body = batch.flat_map { |event| bulk_action(event) }
        response = RelaySearch::Client.client.bulk(body:)

        # Check for bulk errors
        if response["errors"]
          failed_items = response["items"].select { |item| item.dig("index", "error") }
          errors.concat(failed_items.map { |item| item.dig("index", "error", "reason") })
        end

        indexed += batch.size
        logger.info "Indexed events", count: indexed
      end

      if errors.any?
        logger.warn "Bulk index errors", error_count: errors.size, sample: errors.first(5).join(", ")
      end

      Success(indexed:, errors: errors.size)
    rescue StandardError => e
      logger.error "Failed", error: e.message
      Failure(:bulk_index_error)
    end

    private

    def bulk_action(event)
      [
        { index: { _index: RelaySearch::IndexConfig::INDEX_NAME, _id: event.event_id } },
        {
          event_id: event.event_id,
          pubkey: event.pubkey,
          kind: event.kind,
          content: event.content,
          tags: event.tags.filter_map { |t| t[1] if t.is_a?(Array) && t.size >= 2 },
          nostr_created_at: event.nostr_created_at.to_i
        }
      ]
    end
  end
end
