# frozen_string_literal: true

module Search
  class IndexEvent < BaseService
    option :event, type: Types::Instance(Event)

    def call
      return Success(:search_disabled) unless RelaySearch::Client.available?

      RelaySearch::Client.client.index(
        index: RelaySearch::IndexConfig::INDEX_NAME,
        id: event.event_id,
        body: document_body
      )

      Success(event_id: event.event_id)
    rescue StandardError => e
      # Log but don't fail - search indexing is non-critical
      Rails.logger.warn "[Search::IndexEvent] Failed: #{e.message}"
      Success(skipped: true, reason: "indexing_error")
    end

    private

    def document_body
      {
        event_id: event.event_id,
        pubkey: event.pubkey,
        kind: event.kind,
        content: event.content,
        tags: extract_searchable_tags,
        nostr_created_at: event.nostr_created_at.to_i
      }
    end

    def extract_searchable_tags
      event.tags.filter_map { |t| t[1] if t.is_a?(Array) && t.size >= 2 }
    end
  end
end
