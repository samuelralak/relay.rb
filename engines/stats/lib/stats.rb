# frozen_string_literal: true

require "stats/engine"

module Stats
  class << self
    # Configuration accessors
    attr_accessor :event_class_name
    attr_accessor :connection_registry_class_name
    attr_accessor :subscriptions_class_name
    attr_accessor :authentication_enabled
    attr_accessor :dashboard_title

    # Block-style configuration
    # @example
    #   Stats.configure do |config|
    #     config.dashboard_title = "My Relay Stats"
    #     config.authentication_enabled = true
    #   end
    def configure
      yield self
    end

    def event_class
      event_class_name.constantize
    end

    def connection_registry
      connection_registry_class_name.constantize
    end

    def subscriptions
      subscriptions_class_name.constantize
    end

    def authentication_enabled?
      authentication_enabled
    end
  end

  # Defaults
  self.event_class_name = "Event"
  self.connection_registry_class_name = "NostrRelay::ConnectionRegistry"
  self.subscriptions_class_name = "NostrRelay::Subscriptions"
  self.authentication_enabled = false
  self.dashboard_title = "Relay Stats"
end
