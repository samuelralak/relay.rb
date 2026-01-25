# frozen_string_literal: true

# NIP-50: OpenSearch index configuration
module RelaySearch
  module IndexConfig
    INDEX_NAME = ENV.fetch("OPENSEARCH_INDEX", "nostr_events")

    MAPPINGS = {
      properties: {
        event_id: { type: "keyword" },
        pubkey: { type: "keyword" },
        kind: { type: "integer" },
        content: {
          type: "text",
          analyzer: "standard",
          fields: { keyword: { type: "keyword", ignore_above: 256 } }
        },
        tags: { type: "keyword" },
        nostr_created_at: { type: "date", format: "epoch_second" }
      }
    }.freeze

    SETTINGS = {
      number_of_shards: ENV.fetch("OPENSEARCH_SHARDS", 1).to_i,
      number_of_replicas: ENV.fetch("OPENSEARCH_REPLICAS", 0).to_i
    }.freeze
  end
end
