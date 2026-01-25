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
      created_at_grace_period: 900 # 15 minutes tolerance for future timestamps
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

      # Access the limitation section
      def limitation
        (relay_info || {})[:limitation] || {}
      end

      # Individual limit accessors with sensible defaults
      def max_message_length
        limitation[:max_message_length] || DEFAULTS[:max_message_length]
      end

      def max_subscriptions
        limitation[:max_subscriptions] || DEFAULTS[:max_subscriptions]
      end

      def max_subid_length
        limitation[:max_subid_length] || DEFAULTS[:max_subid_length]
      end

      def max_filters
        limitation[:max_filters] || DEFAULTS[:max_filters]
      end

      def max_limit
        limitation[:max_limit] || DEFAULTS[:max_limit]
      end

      def max_event_tags
        limitation[:max_event_tags] || DEFAULTS[:max_event_tags]
      end

      def max_content_length
        limitation[:max_content_length] || DEFAULTS[:max_content_length]
      end

      def default_limit
        limitation[:default_limit] || DEFAULTS[:default_limit]
      end

      def created_at_grace_period
        limitation[:created_at_grace_period] || DEFAULTS[:created_at_grace_period]
      end

      def auth_required?
        limitation[:auth_required] || false
      end

      def payment_required?
        limitation[:payment_required] || false
      end

      # Relay metadata accessors
      def name
        (relay_info || {})[:name]
      end

      def description
        (relay_info || {})[:description]
      end

      def pubkey
        (relay_info || {})[:pubkey]
      end

      def contact
        (relay_info || {})[:contact]
      end

      def supported_nips
        (relay_info || {})[:supported_nips] || []
      end

      def software
        (relay_info || {})[:software]
      end

      def version
        (relay_info || {})[:version]
      end
    end
  end

  class ConfigurationError < StandardError; end
end
