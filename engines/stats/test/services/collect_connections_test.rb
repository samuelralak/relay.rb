# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../app/services/stats/collect_connections"

module Stats
  class CollectConnectionsTest < Minitest::Test
    def setup
      MockClasses::MockConnectionRegistry.mock_count = 5
      MockClasses::MockConnectionRegistry.mock_connections = [
        {
          id: "uuid-1",
          ip_address: "192.168.1.1",
          connected_at: Time.now,
          authenticated_pubkeys: ["pubkey1"],
          subscription_count: 3
        },
        {
          id: "uuid-2",
          ip_address: "192.168.1.2",
          connected_at: Time.now,
          authenticated_pubkeys: [],
          subscription_count: 1
        }
      ]
      MockClasses::MockSubscriptions.mock_total_count = 10
    end

    def test_returns_success_result
      result = CollectConnections.call

      assert result.success?, "Expected success, got: #{result.failure}"
    end

    def test_includes_total_connections
      result = CollectConnections.call

      assert_equal 5, result.value![:total]
    end

    def test_includes_connection_details
      result = CollectConnections.call

      details = result.value![:details]
      assert_equal 2, details.size
      assert_equal "uuid-1", details.first[:id]
      assert_equal "192.168.1.1", details.first[:ip_address]
    end

    def test_includes_total_subscriptions
      result = CollectConnections.call

      assert_equal 10, result.value![:total_subscriptions]
    end

    def test_handles_empty_connections
      MockClasses::MockConnectionRegistry.mock_count = 0
      MockClasses::MockConnectionRegistry.mock_connections = []

      result = CollectConnections.call

      assert result.success?
      assert_equal 0, result.value![:total]
      assert_empty result.value![:details]
    end
  end
end
