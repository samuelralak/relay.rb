# frozen_string_literal: true

# Load Negentropy protocol library for set reconciliation
require "negentropy"

# Configure RelaySync library for syncing events with upstream Nostr relays
require "relay_sync"

RelaySync.configure do |config|
  config.load_from_yaml(Rails.root.join("config/relays.yml"), Rails.env)
end

# Configure logging to use Rails logger
RelaySync::Connection.logger = Rails.logger
RelaySync::Manager.logger = Rails.logger
