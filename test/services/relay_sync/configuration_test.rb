# frozen_string_literal: true

require "test_helper"

module RelaySync
  class ConfigurationTest < ActiveSupport::TestCase
    test "loads configuration from relays.yml" do
      config = Configuration.new

      assert_respond_to config, :upstream_relays
      assert_respond_to config, :sync_settings
    end

    test "upstream_relays returns array of RelayConfig objects" do
      config = Configuration.new

      assert_kind_of Array, config.upstream_relays
      config.upstream_relays.each do |relay|
        assert_kind_of Configuration::RelayConfig, relay
      end
    end

    test "sync_settings returns SyncSettings object" do
      config = Configuration.new

      assert_kind_of Configuration::SyncSettings, config.sync_settings
    end

    test "enabled_relays filters disabled relays" do
      config = Configuration.new
      enabled = config.enabled_relays

      assert_kind_of Array, enabled
      enabled.each do |relay|
        assert relay.enabled?
      end
    end

    test "backfill_relays returns enabled relays with backfill" do
      config = Configuration.new
      backfill = config.backfill_relays

      assert_kind_of Array, backfill
      backfill.each do |relay|
        assert relay.enabled?
        assert relay.backfill?
      end
    end

    test "negentropy_relays returns enabled relays with negentropy" do
      config = Configuration.new
      neg_relays = config.negentropy_relays

      assert_kind_of Array, neg_relays
      neg_relays.each do |relay|
        assert relay.enabled?
        assert relay.negentropy?
      end
    end

    test "download_relays returns relays with download direction" do
      config = Configuration.new
      downloads = config.download_relays

      assert_kind_of Array, downloads
      downloads.each do |relay|
        assert relay.enabled?
        assert relay.download_enabled?
      end
    end

    test "upload_relays returns relays with upload direction" do
      config = Configuration.new
      uploads = config.upload_relays

      assert_kind_of Array, uploads
      uploads.each do |relay|
        assert relay.enabled?
        assert relay.upload_enabled?
      end
    end

    test "find_relay finds by URL" do
      config = Configuration.new

      # Skip if no relays configured
      skip "No relays configured in test environment" if config.upstream_relays.empty?

      first_relay = config.upstream_relays.first
      found = config.find_relay(first_relay.url)

      assert_equal first_relay, found
    end

    test "find_relay returns nil for unknown URL" do
      config = Configuration.new

      assert_nil config.find_relay("wss://unknown.relay.com")
    end
  end

  class RelayConfigTest < ActiveSupport::TestCase
    test "initializes with defaults" do
      config = Configuration::RelayConfig.new(url: "wss://test.relay.com")

      assert_equal "wss://test.relay.com", config.url
      assert config.enabled?
      assert config.backfill?
      assert_not config.negentropy?
      assert_equal "down", config.direction
    end

    test "initializes with custom values" do
      config = Configuration::RelayConfig.new(
        url: "wss://custom.relay.com",
        enabled: false,
        backfill: false,
        negentropy: true,
        direction: "both"
      )

      assert_equal "wss://custom.relay.com", config.url
      assert_not config.enabled?
      assert_not config.backfill?
      assert config.negentropy?
      assert_equal "both", config.direction
    end

    test "download_enabled? returns true for down direction" do
      config = Configuration::RelayConfig.new(url: "wss://test.relay.com", direction: "down")
      assert config.download_enabled?
    end

    test "download_enabled? returns true for both direction" do
      config = Configuration::RelayConfig.new(url: "wss://test.relay.com", direction: "both")
      assert config.download_enabled?
    end

    test "download_enabled? returns false for up direction" do
      config = Configuration::RelayConfig.new(url: "wss://test.relay.com", direction: "up")
      assert_not config.download_enabled?
    end

    test "upload_enabled? returns true for up direction" do
      config = Configuration::RelayConfig.new(url: "wss://test.relay.com", direction: "up")
      assert config.upload_enabled?
    end

    test "upload_enabled? returns true for both direction" do
      config = Configuration::RelayConfig.new(url: "wss://test.relay.com", direction: "both")
      assert config.upload_enabled?
    end

    test "upload_enabled? returns false for down direction" do
      config = Configuration::RelayConfig.new(url: "wss://test.relay.com", direction: "down")
      assert_not config.upload_enabled?
    end

    test "to_h returns hash representation" do
      config = Configuration::RelayConfig.new(
        url: "wss://test.relay.com",
        enabled: true,
        backfill: true,
        negentropy: true,
        direction: "both"
      )

      hash = config.to_h

      assert_equal "wss://test.relay.com", hash[:url]
      assert hash[:enabled]
      assert hash[:backfill]
      assert hash[:negentropy]
      assert_equal "both", hash[:direction]
    end
  end

  class SyncSettingsTest < ActiveSupport::TestCase
    test "initializes with defaults" do
      settings = Configuration::SyncSettings.new({})

      assert_equal 100, settings.batch_size
      assert_equal 10, settings.max_concurrent_connections
      assert_equal 5, settings.reconnect_delay_seconds
      assert_equal 10, settings.max_reconnect_attempts
      assert_equal 168, settings.backfill_since_hours
      assert_equal [0, 1, 3, 5, 6, 7], settings.event_kinds
      assert_equal 60_000, settings.negentropy_frame_size
      assert_equal 50, settings.upload_batch_size
      assert_equal 100, settings.upload_delay_ms
    end

    test "initializes with custom values" do
      settings = Configuration::SyncSettings.new(
        batch_size: 50,
        max_concurrent_connections: 5,
        reconnect_delay_seconds: 10,
        max_reconnect_attempts: 20,
        backfill_since_hours: 24,
        event_kinds: [1, 30023],
        negentropy_frame_size: 30_000,
        upload_batch_size: 25,
        upload_delay_ms: 200
      )

      assert_equal 50, settings.batch_size
      assert_equal 5, settings.max_concurrent_connections
      assert_equal 10, settings.reconnect_delay_seconds
      assert_equal 20, settings.max_reconnect_attempts
      assert_equal 24, settings.backfill_since_hours
      assert_equal [1, 30023], settings.event_kinds
      assert_equal 30_000, settings.negentropy_frame_size
      assert_equal 25, settings.upload_batch_size
      assert_equal 200, settings.upload_delay_ms
    end

    test "backfill_since returns duration" do
      settings = Configuration::SyncSettings.new(backfill_since_hours: 24)

      assert_equal 24.hours, settings.backfill_since
    end

    test "upload_delay returns seconds as float" do
      settings = Configuration::SyncSettings.new(upload_delay_ms: 150)

      assert_equal 0.15, settings.upload_delay
    end

    test "to_h returns hash representation" do
      settings = Configuration::SyncSettings.new(batch_size: 200)

      hash = settings.to_h

      assert_equal 200, hash[:batch_size]
      assert hash.key?(:max_concurrent_connections)
      assert hash.key?(:event_kinds)
    end
  end
end
