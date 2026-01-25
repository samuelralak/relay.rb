# frozen_string_literal: true

require_relative "relay_search/client"
require_relative "relay_search/index_config"

# NIP-50: Search Capability
# OpenSearch integration for full-text search across event content
module RelaySearch
  class Error < StandardError; end
end
