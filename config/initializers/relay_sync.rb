# frozen_string_literal: true

# Configure RelaySync library for syncing events with upstream Nostr relays
# The library is defined in lib/relay_sync.rb, this initializer only configures it

require_relative "../../lib/relay_sync"

RelaySync.configure do |config|
  config.load_from_yaml(Rails.root.join("config/relays.yml"), Rails.env)
end

# Configure logging to use Rails logger
RelaySync::Connection.logger = Rails.logger
RelaySync::Manager.logger = Rails.logger
