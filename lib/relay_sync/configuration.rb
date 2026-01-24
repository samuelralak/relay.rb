# frozen_string_literal: true

require "yaml"

module RelaySync
  class Configuration
    attr_reader :upstream_relays, :sync_settings

    def initialize
      @upstream_relays = []
      @sync_settings = SyncSettings.new({})
    end

    # Load configuration from a YAML file
    # @param path [String, Pathname] path to YAML file
    # @param env [String] environment key to load
    def load_from_yaml(path, env = "development")
      raw = YAML.load_file(path, aliases: true)
      config = raw[env.to_s] || raw["default"] || {}
      load_from_hash(deep_symbolize_keys(config))
    end

    # Load configuration from a hash
    # @param config [Hash] configuration hash
    def load_from_hash(config)
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
      relays.map { |r| RelayConfig.new(deep_symbolize_keys(r)) }
    end

    def deep_symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        new_key = key.to_sym
        new_value = case value
        when Hash then deep_symbolize_keys(value)
        when Array then value.map { |v| v.is_a?(Hash) ? deep_symbolize_keys(v) : v }
        else value
        end
        result[new_key] = new_value
      end
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
        %w[down both].include?(direction)
      end

      def upload_enabled?
        %w[up both].include?(direction)
      end

      def to_h
        {
          url:,
          enabled: enabled?,
          backfill: backfill?,
          negentropy: negentropy?,
          direction:
        }
      end
    end

    class SyncSettings
      attr_reader :batch_size, :max_concurrent_connections, :reconnect_delay_seconds,
                  :max_reconnect_attempts, :backfill_since_hours, :event_kinds,
                  :negentropy_frame_size, :negentropy_chunk_hours, :upload_batch_size, :upload_delay_ms,
                  :resume_overlap_seconds, :checkpoint_interval,
                  :polling_window_minutes, :polling_timeout_seconds,
                  :stale_threshold_minutes, :error_retry_after_minutes

      def initialize(config)
        @batch_size = config.fetch(:batch_size, 100)
        @max_concurrent_connections = config.fetch(:max_concurrent_connections, 10)
        @reconnect_delay_seconds = config.fetch(:reconnect_delay_seconds, 5)
        @max_reconnect_attempts = config.fetch(:max_reconnect_attempts, 10)
        @backfill_since_hours = config.fetch(:backfill_since_hours, 168)
        @event_kinds = config.fetch(:event_kinds, [ 0, 1, 3, 5, 6, 7 ])
        @negentropy_frame_size = config.fetch(:negentropy_frame_size, 60_000)
        @negentropy_chunk_hours = config.fetch(:negentropy_chunk_hours, 168) # 1 week default
        @upload_batch_size = config.fetch(:upload_batch_size, 50)
        @upload_delay_ms = config.fetch(:upload_delay_ms, 100)
        # Robustness settings
        @resume_overlap_seconds = config.fetch(:resume_overlap_seconds, 300) # 5 minutes overlap on resume
        @checkpoint_interval = config.fetch(:checkpoint_interval, 100) # Save progress every N events
        # Polling settings for job-based sync orchestration
        @polling_window_minutes = config.fetch(:polling_window_minutes, 15)
        @polling_timeout_seconds = config.fetch(:polling_timeout_seconds, 30)
        @stale_threshold_minutes = config.fetch(:stale_threshold_minutes, 10)
        @error_retry_after_minutes = config.fetch(:error_retry_after_minutes, 30)

        validate!
      end

      private

      def validate!
        raise ConfigurationError, "batch_size must be positive" if @batch_size <= 0
        raise ConfigurationError, "backfill_since_hours must be positive" if @backfill_since_hours <= 0
        raise ConfigurationError, "negentropy_chunk_hours must be positive" if @negentropy_chunk_hours <= 0
        raise ConfigurationError, "stale_threshold_minutes must be positive" if @stale_threshold_minutes <= 0
        raise ConfigurationError, "polling_timeout_seconds must be positive" if @polling_timeout_seconds <= 0
      end

      public

      # Returns backfill duration in seconds
      def backfill_since
        backfill_since_hours * 3600
      end

      def upload_delay
        upload_delay_ms / 1000.0
      end

      def to_h
        {
          batch_size:,
          max_concurrent_connections:,
          reconnect_delay_seconds:,
          max_reconnect_attempts:,
          backfill_since_hours:,
          event_kinds:,
          negentropy_frame_size:,
          upload_batch_size:,
          upload_delay_ms:,
          resume_overlap_seconds:,
          checkpoint_interval:,
          polling_window_minutes:,
          polling_timeout_seconds:,
          stale_threshold_minutes:,
          error_retry_after_minutes:
        }
      end
    end
  end
end
