# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../app/services/stats/collect_connections"
require_relative "../../app/services/stats/collect_events"
require_relative "../../app/services/stats/collect_system"
require_relative "../../app/services/stats/collect_overview"

module Stats
  class CollectOverviewTest < Minitest::Test
    def setup
      Rails.cache.clear

      # Reset mocks
      MockClasses::MockConnectionRegistry.mock_count = 5
      MockClasses::MockConnectionRegistry.mock_connections = [
        {
          id: "test-uuid",
          ip_address: "192.168.1.1",
          connected_at: Time.now,
          authenticated_pubkeys: [],
          subscription_count: 2
        }
      ]
      MockClasses::MockSubscriptions.mock_total_count = 10
      MockClasses::MockEvent.mock_count = 1000
      MockClasses::MockEvent.mock_by_kind = { 1 => 500 }
      MockClasses::MockEvent.mock_last_7_days = { Date.today.to_s => 100 }
    end

    def test_returns_success_result
      result = CollectOverview.call

      assert result.success?, "Expected success, got: #{result.failure}"
    end

    def test_includes_all_sections
      result = CollectOverview.call
      value = result.value!

      assert value.key?(:connections), "Missing :connections key"
      assert value.key?(:events), "Missing :events key"
      assert value.key?(:system), "Missing :system key"
      assert value.key?(:collected_at), "Missing :collected_at key"
    end

    def test_connections_section_has_required_fields
      result = CollectOverview.call
      connections = result.value![:connections]

      assert connections.key?(:total)
      assert connections.key?(:details)
      assert connections.key?(:total_subscriptions)
    end

    def test_events_section_has_required_fields
      result = CollectOverview.call
      events = result.value![:events]

      assert events.key?(:total)
      assert events.key?(:today)
      assert events.key?(:per_minute)
      assert events.key?(:by_kind)
      assert events.key?(:last_7_days)
    end

    def test_system_section_has_required_fields
      result = CollectOverview.call
      system = result.value![:system]

      assert system.key?(:memory)
      assert system.key?(:cpu)
      assert system.key?(:process)
      assert system.key?(:database)
    end

    def test_collected_at_is_iso8601_format
      result = CollectOverview.call
      collected_at = result.value![:collected_at]

      # Should be parseable as ISO8601
      assert_match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, collected_at)
    end

    def test_aggregates_data_from_sub_services
      result = CollectOverview.call
      value = result.value!

      # Verify data flows through correctly
      assert_equal 5, value[:connections][:total]
      assert_equal 1000, value[:events][:total]
      assert_equal Process.pid, value[:system][:process][:pid]
    end
  end
end
