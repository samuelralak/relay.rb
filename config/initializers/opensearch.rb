# frozen_string_literal: true

require "relay_search"

Rails.application.config.after_initialize do
  if RelaySearch::Client.enabled?
    AppLogger[:OpenSearch].info "Configured", url: ENV["OPENSEARCH_URL"]
    AppLogger[:OpenSearch].info "Available", status: RelaySearch::Client.available?
  else
    AppLogger[:OpenSearch].info "Disabled (OPENSEARCH_URL not set)"
  end
end
