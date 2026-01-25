# frozen_string_literal: true

require "test_helper"

module RelaySync
  class ConfigurationTest < ActiveSupport::TestCase
    setup do
      @config = Configuration.new
      @config.relay_provider = UpstreamRelay

      # Create test relays
      @enabled_relay = UpstreamRelay.create!(
        url: "wss://enabled.relay.test",
        enabled: true,
        backfill: true,
        negentropy: true,
        direction: UpstreamRelays::Directions::DOWN
      )
      @disabled_relay = UpstreamRelay.create!(
        url: "wss://disabled.relay.test",
        enabled: false,
        backfill: true,
        negentropy: false,
        direction: UpstreamRelays::Directions::DOWN
      )
      @upload_relay = UpstreamRelay.create!(
        url: "wss://upload.relay.test",
        enabled: true,
        backfill: false,
        negentropy: false,
        direction: UpstreamRelays::Directions::UP
      )
      @both_relay = UpstreamRelay.create!(
        url: "wss://both.relay.test",
        enabled: true,
        backfill: true,
        negentropy: false,
        direction: UpstreamRelays::Directions::BOTH
      )
    end

    teardown do
      UpstreamRelay.delete_all
    end

    test "responds to relay_provider" do
      assert_respond_to @config, :relay_provider
      assert_respond_to @config, :sync_settings
    end

    test "enabled_relays filters disabled relays" do
      enabled = @config.enabled_relays

      assert_includes enabled, @enabled_relay
      assert_includes enabled, @upload_relay
      assert_includes enabled, @both_relay
      assert_not_includes enabled, @disabled_relay
    end

    test "backfill_relays returns enabled relays with backfill" do
      backfill = @config.backfill_relays

      assert_includes backfill, @enabled_relay
      assert_includes backfill, @both_relay
      assert_not_includes backfill, @upload_relay
      assert_not_includes backfill, @disabled_relay
    end

    test "negentropy_relays returns enabled relays with negentropy" do
      neg_relays = @config.negentropy_relays

      assert_includes neg_relays, @enabled_relay
      assert_not_includes neg_relays, @both_relay
      assert_not_includes neg_relays, @disabled_relay
    end

    test "download_relays returns relays with download direction" do
      downloads = @config.download_relays

      assert_includes downloads, @enabled_relay
      assert_includes downloads, @both_relay
      assert_not_includes downloads, @upload_relay
    end

    test "upload_relays returns relays with upload direction" do
      uploads = @config.upload_relays

      assert_includes uploads, @upload_relay
      assert_includes uploads, @both_relay
      assert_not_includes uploads, @enabled_relay
    end

    test "find_relay finds by URL" do
      found = @config.find_relay(@enabled_relay.url)
      assert_equal @enabled_relay, found
    end

    test "find_relay returns nil for unknown URL" do
      assert_nil @config.find_relay("wss://unknown.relay.com")
    end

    test "sync_settings returns Config struct with defaults" do
      settings = @config.sync_settings

      assert_kind_of UpstreamRelays::Config, settings
      assert_equal 100, settings.batch_size
      assert_equal 10, settings.max_concurrent_connections
    end
  end

  class UpstreamRelayConfigTest < ActiveSupport::TestCase
    setup do
      @relay = UpstreamRelay.new(
        url: "wss://test.relay.com",
        enabled: true,
        backfill: true,
        negentropy: true,
        direction: UpstreamRelays::Directions::BOTH
      )
    end

    test "config returns Dry::Struct with defaults" do
      config = @relay.config

      assert_kind_of UpstreamRelays::Config, config
      assert_equal 100, config.batch_size
      assert_equal 10, config.max_concurrent_connections
    end

    test "config respects overrides" do
      @relay.config = { "batch_size" => 50, "max_concurrent_connections" => 5 }
      config = @relay.config

      assert_equal 50, config.batch_size
      assert_equal 5, config.max_concurrent_connections
    end

    test "download_enabled? returns true for down direction" do
      @relay.direction = UpstreamRelays::Directions::DOWN
      assert @relay.download_enabled?
    end

    test "download_enabled? returns true for both direction" do
      @relay.direction = UpstreamRelays::Directions::BOTH
      assert @relay.download_enabled?
    end

    test "download_enabled? returns false for up direction" do
      @relay.direction = UpstreamRelays::Directions::UP
      assert_not @relay.download_enabled?
    end

    test "upload_enabled? returns true for up direction" do
      @relay.direction = UpstreamRelays::Directions::UP
      assert @relay.upload_enabled?
    end

    test "upload_enabled? returns true for both direction" do
      @relay.direction = UpstreamRelays::Directions::BOTH
      assert @relay.upload_enabled?
    end

    test "upload_enabled? returns false for down direction" do
      @relay.direction = UpstreamRelays::Directions::DOWN
      assert_not @relay.upload_enabled?
    end
  end

  class ConfigStructTest < ActiveSupport::TestCase
    test "initializes with defaults" do
      config = UpstreamRelays::Config.new({})

      assert_equal 100, config.batch_size
      assert_equal 10, config.max_concurrent_connections
      assert_equal 5, config.reconnect_delay_seconds
      assert_equal 10, config.max_reconnect_attempts
      assert_equal 43_800, config.backfill_since_hours
      assert_equal [ 0, 1, 3, 5, 6, 7, 30_023 ], config.event_kinds
      assert_equal 60_000, config.negentropy_frame_size
      assert_equal 50, config.upload_batch_size
      assert_equal 100, config.upload_delay_ms
    end

    test "initializes with custom values" do
      config = UpstreamRelays::Config.new(
        batch_size: 50,
        max_concurrent_connections: 5,
        reconnect_delay_seconds: 10,
        max_reconnect_attempts: 20,
        backfill_since_hours: 24,
        event_kinds: [ 1, 30_023 ],
        negentropy_frame_size: 30_000,
        upload_batch_size: 25,
        upload_delay_ms: 200
      )

      assert_equal 50, config.batch_size
      assert_equal 5, config.max_concurrent_connections
      assert_equal 10, config.reconnect_delay_seconds
      assert_equal 20, config.max_reconnect_attempts
      assert_equal 24, config.backfill_since_hours
      assert_equal [ 1, 30_023 ], config.event_kinds
      assert_equal 30_000, config.negentropy_frame_size
      assert_equal 25, config.upload_batch_size
      assert_equal 200, config.upload_delay_ms
    end

    test "backfill_since returns duration in seconds" do
      config = UpstreamRelays::Config.new(backfill_since_hours: 24)
      assert_equal 24 * 3600, config.backfill_since
    end

    test "upload_delay returns seconds as float" do
      config = UpstreamRelays::Config.new(upload_delay_ms: 150)
      assert_equal 0.15, config.upload_delay
    end

    test "reconnect_delay returns seconds" do
      config = UpstreamRelays::Config.new(reconnect_delay_seconds: 10)
      assert_equal 10, config.reconnect_delay
    end
  end
end
