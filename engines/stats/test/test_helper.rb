# frozen_string_literal: true

# Configure Rails environment for testing
ENV["RAILS_ENV"] = "test"

require "bundler/setup"
require "dry-monads"
require "dry-initializer"
require "active_support"
require "active_support/core_ext/time"
require "active_support/core_ext/date"
require "active_support/core_ext/numeric/time"
require "active_support/cache"
require "minitest/autorun"
require "minitest/spec"

# Mock BaseService from host app
class BaseService
  extend Dry::Initializer
  include Dry::Monads[:result]

  def self.call(...)
    new(...).call
  end

  def call
    raise NotImplementedError
  end
end

# Define Stats module without loading the full engine
module Stats
  # Configuration accessors
  class << self
    attr_accessor :event_class_name, :connection_registry_class_name, :subscriptions_class_name
    attr_accessor :authentication_enabled, :dashboard_title

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
end

# Mock classes for testing without full Rails app
module MockClasses
  class MockEvent
    class << self
      attr_accessor :mock_count, :mock_today_count, :mock_recent_count,
                    :mock_by_kind, :mock_last_7_days

      def count
        mock_count || 1000
      end

      def where(*)
        self
      end

      def group(method)
        MockGroupResult.new(self, method)
      end
    end
  end

  class MockGroupResult
    def initialize(klass, method)
      @klass = klass
      @method = method.to_s.include?("DATE") ? :date : method.to_sym
    end

    def count
      case @method
      when :kind
        @klass.mock_by_kind || { 1 => 500, 4 => 300, 30023 => 200 }
      else
        @klass.mock_last_7_days || { Date.current.to_s => 100 }
      end
    end

    def group(method)
      @method = method.to_s.include?("DATE") ? :date : method.to_sym
      self
    end
  end

  class MockConnectionRegistry
    class << self
      attr_accessor :mock_connections, :mock_count

      def connection_count
        mock_count || 5
      end

      def connection_details
        mock_connections || [
          {
            id: "test-uuid-1",
            ip_address: "192.168.1.1",
            connected_at: Time.current,
            authenticated_pubkeys: [],
            subscription_count: 2
          }
        ]
      end
    end
  end

  class MockSubscriptions
    class << self
      attr_accessor :mock_total_count

      def total_subscription_count
        mock_total_count || 10
      end

      def subscription_count_for(_connection_id)
        2
      end
    end
  end
end

# Configure Stats module to use mocks
module Stats
  self.event_class_name = "MockClasses::MockEvent"
  self.connection_registry_class_name = "MockClasses::MockConnectionRegistry"
  self.subscriptions_class_name = "MockClasses::MockSubscriptions"
  self.authentication_enabled = false
  self.dashboard_title = "Test Relay Stats"
end

# Stub Rails for testing
module Rails
  def self.cache
    @cache ||= ActiveSupport::Cache::MemoryStore.new
  end

  def self.logger
    @logger ||= Logger.new($stdout, level: :warn)
  end

  def self.version
    "8.1.1"
  end

  def self.application
    @application ||= MockApplication.new
  end

  class MockApplication
    def initialized_at
      Time.now - 3600 # 1 hour ago
    end

    def respond_to?(method)
      method == :initialized_at || super
    end
  end
end

# Mock ActiveRecord for testing
module ActiveRecord
  class Base
    def self.connection_pool
      MockConnectionPool.new
    end
  end

  class MockConnectionPool
    def size
      10
    end

    def connections
      [MockConnection.new(true), MockConnection.new(false)]
    end

    def num_waiting_in_queue
      0
    end
  end

  class MockConnection
    def initialize(in_use)
      @in_use = in_use
    end

    def in_use?
      @in_use
    end
  end
end
