# frozen_string_literal: true

module RelaySync
  class Configuration
    attr_accessor :relay_provider
    attr_writer :relay_private_key

    # Delegate relay queries to provider
    def enabled_relays      = relay_provider.enabled
    def backfill_relays     = relay_provider.backfill_capable
    def negentropy_relays   = relay_provider.negentropy_capable
    def download_relays     = relay_provider.download_capable
    def upload_relays       = relay_provider.upload_capable
    def find_relay(url)     = relay_provider.find_by_url(url)

    # Returns default sync settings (Dry::Struct with defaults)
    # For per-relay settings, use relay.config instead
    def sync_settings
      @sync_settings ||= relay_provider.new.config
    end

    # NIP-42: Private key for authenticating to upstream relays
    # Can be set via configuration or environment variable
    def relay_private_key
      @relay_private_key || ENV["RELAY_PRIVATE_KEY"]
    end
  end
end
