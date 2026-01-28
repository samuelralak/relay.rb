# frozen_string_literal: true

require "logger"

module NostrRelay
  # Centralized access to NIP-11 relay configuration and application adapters.
  # Framework-agnostic: the application configures via configure block.
  #
  # Usage in Rails initializer:
  #   NostrRelay::Config.configure do |config|
  #     config.relay_info = Rails.application.config.relay_info
  #     config.logger = Rails.logger
  #
  #     # Adapters - application provides implementations matching expected API
  #     config.event_repository = Event
  #     config.event_serializer = Events::EventSerializer
  #     config.event_processor = Events::ProcessIncoming
  #   end
  module Config
    # Default values for NIP-11 limitation fields
    DEFAULTS = {
      max_message_length: 16_384,
      max_subscriptions: 20,
      max_subid_length: 64,
      max_filters: 10,
      max_limit: 5_000,
      max_event_tags: 100,
      max_content_length: 65_535,
      default_limit: 500,
      created_at_grace_period: 900, # 15 minutes tolerance for future timestamps
      search_query_max_length: 256, # NIP-50: Maximum search query length
      search_max_limit: 500,        # NIP-50: Maximum search results
      ping_interval: 30             # WebSocket ping interval in seconds (keeps connections alive)
    }.freeze

    class << self
      attr_accessor :relay_info

      # Adapters for application-layer dependencies
      # event_repository: responds to .matching_filters(filters) returning events
      # event_serializer: responds to .serialize(event) returning hash
      # event_processor: responds to .call(event_data:) returning result
      # logger: responds to .info, .error, .warn, .debug
      attr_accessor :event_repository, :event_serializer, :event_processor
      attr_writer :logger

      def configure
        yield self
      end

      # Logger with null logger fallback
      def logger
        @logger ||= ::Logger.new(File::NULL)
      end

      # Reset to defaults (useful for testing)
      def reset!
        @relay_info = nil
        @event_repository = nil
        @event_serializer = nil
        @event_processor = nil
        @logger = nil
      end

      # Validate required adapters are configured
      def validate!
        missing = []
        missing << :event_repository unless event_repository
        missing << :event_serializer unless event_serializer
        missing << :event_processor unless event_processor

        return true if missing.empty?

        raise ConfigurationError, "Missing required adapters: #{missing.join(', ')}"
      end

      # Limitation accessors (with defaults from DEFAULTS)
      def max_message_length    = limit_value(:max_message_length)
      def max_subscriptions     = limit_value(:max_subscriptions)
      def max_subid_length      = limit_value(:max_subid_length)
      def max_filters           = limit_value(:max_filters)
      def max_limit             = limit_value(:max_limit)
      def max_event_tags        = limit_value(:max_event_tags)
      def max_content_length    = limit_value(:max_content_length)
      def default_limit         = limit_value(:default_limit)
      def created_at_grace_period = limit_value(:created_at_grace_period)
      def ping_interval         = limit_value(:ping_interval)
      def auth_required?        = limit_value(:auth_required, false)
      def payment_required?     = limit_value(:payment_required, false)

      # NIP-42: Authentication configuration
      def auth_enabled?         = relay_url.present?
      def relay_url             = metadata(:relay_url) || ENV["RELAY_URL"]
      def auth_timeout          = limit_value(:auth_timeout_seconds, 600)
      def restrict_dm_access?   = limit_value(:restrict_dm_access, false)

      # NIP-50: Search configuration
      def search_enabled?           = RelaySearch::Client.available? rescue false
      def search_query_max_length   = limit_value(:search_query_max_length)
      def search_max_limit          = limit_value(:search_max_limit)

      # Relay metadata accessors
      def name           = metadata(:name)
      def description    = metadata(:description)
      def pubkey         = metadata(:pubkey)
      def contact        = metadata(:contact)
      def supported_nips = metadata(:supported_nips, [])
      def software       = metadata(:software)
      def version        = metadata(:version)

      private

      # Fetch limitation value with fallback to DEFAULTS
      # Uses nil? checks to properly handle explicit false values
      def limit_value(key, default = nil)
        value = relay_info&.dig(:limitation, key)
        return value unless value.nil?
        default.nil? ? DEFAULTS[key] : default
      end

      # Fetch relay metadata with optional default
      def metadata(key, default = nil)
        value = relay_info&.dig(key)
        value.nil? ? default : value
      end
    end
  end

  class ConfigurationError < StandardError; end
end
