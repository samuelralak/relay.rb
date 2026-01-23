# frozen_string_literal: true

# RelaySync module provides functionality for syncing events with upstream Nostr relays
module RelaySync
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def start
      Manager.instance.start
    end

    def stop
      Manager.instance.stop
    end

    def manager
      Manager.instance
    end

    def status
      Manager.instance.status
    end
  end
end
