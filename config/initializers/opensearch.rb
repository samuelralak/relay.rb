# frozen_string_literal: true

require "relay_search"

Rails.application.config.after_initialize do
  if RelaySearch::Client.enabled?
    Rails.logger.info "[OpenSearch] Configured: #{ENV['OPENSEARCH_URL']}"
    Rails.logger.info "[OpenSearch] Available: #{RelaySearch::Client.available?}"
  else
    Rails.logger.info "[OpenSearch] Disabled (OPENSEARCH_URL not set)"
  end
end
