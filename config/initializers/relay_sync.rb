# frozen_string_literal: true

# Load Negentropy protocol library for set reconciliation
require "negentropy"

# Configure RelaySync library for syncing events with upstream Nostr relays
require "relay_sync"

Rails.application.config.after_initialize do
  RelaySync.configure do |config|
    config.relay_provider = UpstreamRelay
  end
end

# Configure logging to use Rails logger
RelaySync::Connection.logger = Rails.logger
RelaySync::Manager.logger = Rails.logger
