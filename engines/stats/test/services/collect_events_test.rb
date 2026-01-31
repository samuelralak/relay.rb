# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../app/services/stats/collect_events"

module Stats
  class CollectEventsTest < Minitest::Test
    def setup
      # Clear cache before each test
      Rails.cache.clear

      MockClasses::MockEvent.mock_count = 1000
      MockClasses::MockEvent.mock_by_kind = { 1 => 500, 4 => 300, 30023 => 200 }
      MockClasses::MockEvent.mock_last_7_days = {
        (Date.current - 6).to_s => 100,
        (Date.current - 5).to_s => 150,
        (Date.current - 4).to_s => 120,
        (Date.current - 3).to_s => 180,
        (Date.current - 2).to_s => 200,
        (Date.current - 1).to_s => 250,
        Date.current.to_s => 100
      }
    end

    def test_returns_success_result
      result = CollectEvents.call

      assert result.success?, "Expected success, got: #{result.failure}"
    end

    def test_includes_total_count
      result = CollectEvents.call

      assert_equal 1000, result.value![:total]
    end

    def test_includes_by_kind_breakdown
      result = CollectEvents.call

      by_kind = result.value![:by_kind]
      assert_equal 500, by_kind[1]
      assert_equal 300, by_kind[4]
      assert_equal 200, by_kind[30023]
    end

    def test_includes_last_7_days
      result = CollectEvents.call

      last_7_days = result.value![:last_7_days]
      assert_equal 7, last_7_days.size
    end

    def test_by_kind_is_cached
      # First call should hit the database
      CollectEvents.call

      # Update the mock data
      MockClasses::MockEvent.mock_by_kind = { 1 => 999 }

      # Second call should return cached data
      result = CollectEvents.call

      # Should still have the original data
      assert_equal 500, result.value![:by_kind][1]
    end

    def test_last_7_days_is_cached
      # First call populates cache
      CollectEvents.call

      # Update the mock data
      MockClasses::MockEvent.mock_last_7_days = { Date.current.to_s => 999 }

      # Second call should return cached data
      result = CollectEvents.call

      # Should still have the original data
      assert_equal 100, result.value![:last_7_days][Date.current.to_s]
    end
  end
end
