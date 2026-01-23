# frozen_string_literal: true

module RelaySync
  class Configuration
    attr_reader :upstream_relays, :sync_settings

    def initialize
      config = Rails.application.config_for(:relays)
      @upstream_relays = build_relay_configs(config[:upstream_relays] || [])
      @sync_settings = SyncSettings.new(config[:sync] || {})
    end

    def enabled_relays
      upstream_relays.select(&:enabled?)
    end

    def backfill_relays
      enabled_relays.select(&:backfill?)
    end

    def negentropy_relays
      enabled_relays.select(&:negentropy?)
    end

    def download_relays
      enabled_relays.select(&:download_enabled?)
    end

    def upload_relays
      enabled_relays.select(&:upload_enabled?)
    end

    def find_relay(url)
      upstream_relays.find { |r| r.url == url }
    end

    private

    def build_relay_configs(relays)
      relays.map { |r| RelayConfig.new(r.deep_symbolize_keys) }
    end

    class RelayConfig
      attr_reader :url, :direction

      def initialize(config)
        @url = config[:url]
        @enabled = config.fetch(:enabled, true)
        @backfill = config.fetch(:backfill, true)
        @negentropy = config.fetch(:negentropy, false)
        @direction = config.fetch(:direction, "down")
      end

      def enabled?
        @enabled
      end

      def backfill?
        @backfill
      end

      def negentropy?
        @negentropy
      end

      def download_enabled?
        direction.in?(%w[down both])
      end

      def upload_enabled?
        direction.in?(%w[up both])
      end

      def to_h
        {
          url: url,
          enabled: enabled?,
          backfill: backfill?,
          negentropy: negentropy?,
          direction: direction
        }
      end
    end

    class SyncSettings
      attr_reader :batch_size, :max_concurrent_connections, :reconnect_delay_seconds,
                  :max_reconnect_attempts, :backfill_since_hours, :event_kinds,
                  :negentropy_frame_size, :upload_batch_size, :upload_delay_ms

      def initialize(config)
        @batch_size = config.fetch(:batch_size, 100)
        @max_concurrent_connections = config.fetch(:max_concurrent_connections, 10)
        @reconnect_delay_seconds = config.fetch(:reconnect_delay_seconds, 5)
        @max_reconnect_attempts = config.fetch(:max_reconnect_attempts, 10)
        @backfill_since_hours = config.fetch(:backfill_since_hours, 168)
        @event_kinds = config.fetch(:event_kinds, [0, 1, 3, 5, 6, 7])
        @negentropy_frame_size = config.fetch(:negentropy_frame_size, 60_000)
        @upload_batch_size = config.fetch(:upload_batch_size, 50)
        @upload_delay_ms = config.fetch(:upload_delay_ms, 100)
      end

      def backfill_since
        backfill_since_hours.hours
      end

      def upload_delay
        upload_delay_ms / 1000.0
      end

      def to_h
        {
          batch_size: batch_size,
          max_concurrent_connections: max_concurrent_connections,
          reconnect_delay_seconds: reconnect_delay_seconds,
          max_reconnect_attempts: max_reconnect_attempts,
          backfill_since_hours: backfill_since_hours,
          event_kinds: event_kinds,
          negentropy_frame_size: negentropy_frame_size,
          upload_batch_size: upload_batch_size,
          upload_delay_ms: upload_delay_ms
        }
      end
    end
  end
end
