# frozen_string_literal: true

require_relative "relay_sync/version"
require_relative "relay_sync/errors"
require_relative "relay_sync/types"
require_relative "relay_sync/configuration"
require_relative "relay_sync/message_handler"
require_relative "relay_sync/reactor"
require_relative "relay_sync/connection"
require_relative "relay_sync/event_publisher"
require_relative "relay_sync/manager"

module RelaySync
  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout, level: Logger::INFO)
    end

    def manager
      Manager.instance
    end

    def reactor
      Reactor.instance
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def reset_configuration!
      @configuration = nil
    end

    # Start the sync manager and connect to all enabled relays
    def start
      logger.info "[RelaySync] Starting sync manager..."

      max_connections = configuration.sync_settings.max_concurrent_connections
      relays_to_connect = configuration.enabled_relays.take(max_connections)

      if relays_to_connect.size < configuration.enabled_relays.size
        logger.warn "[RelaySync] Limited to #{max_connections} connections " \
                    "(#{configuration.enabled_relays.size} relays configured)"
      end

      relays_to_connect.each do |relay_config|
        manager.add_connection(relay_config.url)
      end

      logger.info "[RelaySync] Connecting to #{relays_to_connect.size} relay(s)"
    end

    # Stop all connections
    def stop
      logger.info "[RelaySync] Stopping sync manager..."
      manager.stop
      reactor.stop
    end

    # Get status of all connections and sync states
    def status
      {
        connections: manager.status,
        sync_states: [] # Will be populated by Rails app if SyncState model exists
      }
    end
  end
end
