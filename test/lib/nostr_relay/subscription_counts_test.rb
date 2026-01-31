# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class SubscriptionCountsTest < ActiveSupport::TestCase
    setup do
      Subscriptions.reset!
      @connection1 = NostrTestHelpers::MockConnection.new
      @connection2 = NostrTestHelpers::MockConnection.new
      @connection3 = NostrTestHelpers::MockConnection.new
    end

    teardown do
      Subscriptions.reset!
    end

    # =========================================================================
    # subscription_count_for
    # =========================================================================

    test "subscription_count_for returns 0 for unregistered connection" do
      assert_equal 0, Subscriptions.subscription_count_for("nonexistent")
    end

    test "subscription_count_for returns 0 for connection with no subscriptions" do
      Subscriptions.register(@connection1)
      assert_equal 0, Subscriptions.subscription_count_for(@connection1.id)
    end

    test "subscription_count_for returns correct count for single subscription" do
      Subscriptions.register(@connection1)
      Subscriptions.subscribe(
        connection_id: @connection1.id,
        sub_id: "sub1",
        filters: [ { kinds: [ 1 ] } ]
      )

      assert_equal 1, Subscriptions.subscription_count_for(@connection1.id)
    end

    test "subscription_count_for returns correct count for multiple subscriptions" do
      Subscriptions.register(@connection1)
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub3", filters: [ { kinds: [ 0 ] } ])

      assert_equal 3, Subscriptions.subscription_count_for(@connection1.id)
    end

    test "subscription_count_for updates when subscription is removed" do
      Subscriptions.register(@connection1)
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])

      assert_equal 2, Subscriptions.subscription_count_for(@connection1.id)

      Subscriptions.unsubscribe(@connection1.id, "sub1")

      assert_equal 1, Subscriptions.subscription_count_for(@connection1.id)
    end

    # =========================================================================
    # total_subscription_count
    # =========================================================================

    test "total_subscription_count returns 0 when no connections" do
      assert_equal 0, Subscriptions.total_subscription_count
    end

    test "total_subscription_count returns 0 when connections have no subscriptions" do
      Subscriptions.register(@connection1)
      Subscriptions.register(@connection2)

      assert_equal 0, Subscriptions.total_subscription_count
    end

    test "total_subscription_count returns correct total across all connections" do
      Subscriptions.register(@connection1)
      Subscriptions.register(@connection2)
      Subscriptions.register(@connection3)

      # connection1: 2 subscriptions
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])

      # connection2: 3 subscriptions
      Subscriptions.subscribe(connection_id: @connection2.id, sub_id: "sub1", filters: [ { kinds: [ 0 ] } ])
      Subscriptions.subscribe(connection_id: @connection2.id, sub_id: "sub2", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection2.id, sub_id: "sub3", filters: [ { kinds: [ 3 ] } ])

      # connection3: 0 subscriptions

      assert_equal 5, Subscriptions.total_subscription_count
    end

    test "total_subscription_count updates when subscriptions change" do
      Subscriptions.register(@connection1)
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])

      assert_equal 1, Subscriptions.total_subscription_count

      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])

      assert_equal 2, Subscriptions.total_subscription_count

      Subscriptions.unsubscribe(@connection1.id, "sub1")

      assert_equal 1, Subscriptions.total_subscription_count
    end

    test "total_subscription_count updates when connection is unregistered" do
      Subscriptions.register(@connection1)
      Subscriptions.register(@connection2)

      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection2.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection2.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])

      assert_equal 3, Subscriptions.total_subscription_count

      Subscriptions.unregister(@connection2.id)

      assert_equal 1, Subscriptions.total_subscription_count
    end

    # =========================================================================
    # all_subscription_counts
    # =========================================================================

    test "all_subscription_counts returns empty hash when no subscriptions" do
      assert_equal({}, Subscriptions.all_subscription_counts)
    end

    test "all_subscription_counts returns correct counts for all connections" do
      Subscriptions.register(@connection1)
      Subscriptions.register(@connection2)

      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])
      Subscriptions.subscribe(connection_id: @connection2.id, sub_id: "sub1", filters: [ { kinds: [ 0 ] } ])

      counts = Subscriptions.all_subscription_counts

      assert_equal 2, counts[@connection1.id]
      assert_equal 1, counts[@connection2.id]
    end

    test "all_subscription_counts excludes connections with zero subscriptions" do
      Subscriptions.register(@connection1)
      Subscriptions.register(@connection2)

      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      # connection2 has no subscriptions

      counts = Subscriptions.all_subscription_counts

      assert_equal 1, counts[@connection1.id]
      assert_nil counts[@connection2.id]
    end

    test "all_subscription_counts updates when subscriptions change" do
      Subscriptions.register(@connection1)

      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      assert_equal({ @connection1.id => 1 }, Subscriptions.all_subscription_counts)

      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub2", filters: [ { kinds: [ 7 ] } ])
      assert_equal({ @connection1.id => 2 }, Subscriptions.all_subscription_counts)

      Subscriptions.unsubscribe(@connection1.id, "sub1")
      assert_equal({ @connection1.id => 1 }, Subscriptions.all_subscription_counts)
    end

    # =========================================================================
    # Edge Cases
    # =========================================================================

    test "replacing subscription keeps count consistent" do
      Subscriptions.register(@connection1)

      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])
      assert_equal 1, Subscriptions.subscription_count_for(@connection1.id)

      # Replace with same sub_id
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 7 ] } ])
      assert_equal 1, Subscriptions.subscription_count_for(@connection1.id)
    end

    test "unsubscribing non-existent subscription does not affect count" do
      Subscriptions.register(@connection1)
      Subscriptions.subscribe(connection_id: @connection1.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])

      assert_equal 1, Subscriptions.subscription_count_for(@connection1.id)

      Subscriptions.unsubscribe(@connection1.id, "nonexistent")

      assert_equal 1, Subscriptions.subscription_count_for(@connection1.id)
    end
  end
end
