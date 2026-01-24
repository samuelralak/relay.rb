# frozen_string_literal: true

module RelaySync
  class Error < StandardError; end
  class ConnectionError < Error; end
  class SyncError < Error; end
  class SyncTimeoutError < SyncError; end
  class ConfigurationError < Error; end
  class NegentropyError < Error; end
end
