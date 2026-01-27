# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class RedisPubsubTest < ActiveSupport::TestCase
    setup do
      RedisPubsub.reset!
      Subscriptions.reset!
    end

    teardown do
      RedisPubsub.reset!
      Subscriptions.reset!
    end

    test "enabled? returns false when REDIS_URL not set" do
      with_env("REDIS_URL" => nil) do
        assert_not RedisPubsub.enabled?
      end
    end

    test "enabled? returns true when REDIS_URL is set" do
      with_env("REDIS_URL" => "redis://localhost:6379") do
        assert RedisPubsub.enabled?
      end
    end

    test "worker_id is unique and stable within process" do
      id1 = RedisPubsub.worker_id
      id2 = RedisPubsub.worker_id

      assert_equal id1, id2
      assert_includes id1, Process.pid.to_s
    end

    test "worker_id changes after reset!" do
      id1 = RedisPubsub.worker_id
      RedisPubsub.reset!
      id2 = RedisPubsub.worker_id

      assert_not_equal id1, id2
    end

    test "publish does nothing when Redis disabled" do
      with_env("REDIS_URL" => nil) do
        # Should not raise
        assert_nothing_raised do
          RedisPubsub.publish(type: :event, data: { id: "test" })
        end
      end
    end

    test "publish gracefully fails when Redis unavailable" do
      with_env("REDIS_URL" => "redis://nonexistent-host:6379") do
        # Should not raise, just log
        assert_nothing_raised do
          RedisPubsub.publish(type: :event, data: { id: "test" })
        end
      end
    end

    test "subscriber_alive? returns false when not started" do
      assert_not RedisPubsub.subscriber_alive?
    end

    test "start_subscriber does nothing when Redis disabled" do
      with_env("REDIS_URL" => nil) do
        RedisPubsub.start_subscriber
        assert_not RedisPubsub.subscriber_alive?
      end
    end

    test "stop_subscriber handles nil thread gracefully" do
      assert_nothing_raised do
        RedisPubsub.stop_subscriber
      end
    end

    # =========================================================================
    # Message Handling
    # =========================================================================

    test "handle_message skips messages from same worker" do
      connection = NostrTestHelpers::MockConnection.new
      Subscriptions.register(connection)
      Subscriptions.subscribe(connection_id: connection.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])

      # Create message with same worker_id
      message = {
        type: "event",
        worker_id: RedisPubsub.worker_id,  # Same as current worker
        data: {
          "id" => SecureRandom.hex(32),
          "pubkey" => SecureRandom.hex(32),
          "created_at" => Time.now.to_i,
          "kind" => 1,
          "tags" => [],
          "content" => "test",
          "sig" => SecureRandom.hex(64)
        }
      }.to_json

      # Should skip own message
      RedisPubsub.send(:handle_message, message)

      assert_empty connection.sent_messages
    end

    test "handle_message processes event type from other worker" do
      connection = NostrTestHelpers::MockConnection.new
      Subscriptions.register(connection)
      Subscriptions.subscribe(connection_id: connection.id, sub_id: "sub1", filters: [ { kinds: [ 1 ] } ])

      # Create message with different worker_id
      message = {
        type: "event",
        worker_id: "other-worker-#{SecureRandom.hex(4)}",
        data: {
          "id" => SecureRandom.hex(32),
          "pubkey" => SecureRandom.hex(32),
          "created_at" => Time.now.to_i,
          "kind" => 1,
          "tags" => [],
          "content" => "from other worker",
          "sig" => SecureRandom.hex(64)
        }
      }.to_json

      RedisPubsub.send(:handle_message, message)

      event_messages = connection.sent_messages.select { |m| m[0] == "EVENT" }
      assert_equal 1, event_messages.count
    end

    test "handle_message processes ephemeral type from other worker" do
      connection = NostrTestHelpers::MockConnection.new
      Subscriptions.register(connection)
      Subscriptions.subscribe(connection_id: connection.id, sub_id: "sub1", filters: [ { kinds: [ 20000 ] } ])

      message = {
        type: "ephemeral",
        worker_id: "other-worker-#{SecureRandom.hex(4)}",
        data: {
          "id" => SecureRandom.hex(32),
          "pubkey" => SecureRandom.hex(32),
          "created_at" => Time.now.to_i,
          "kind" => 20000,
          "tags" => [],
          "content" => "ephemeral from other worker",
          "sig" => SecureRandom.hex(64)
        }
      }.to_json

      RedisPubsub.send(:handle_message, message)

      event_messages = connection.sent_messages.select { |m| m[0] == "EVENT" }
      assert_equal 1, event_messages.count
    end

    test "handle_message handles invalid JSON gracefully" do
      assert_nothing_raised do
        RedisPubsub.send(:handle_message, "not valid json {{{")
      end
    end

    test "handle_message handles unknown type gracefully" do
      message = {
        type: "unknown_type",
        worker_id: "other-worker",
        data: {}
      }.to_json

      assert_nothing_raised do
        RedisPubsub.send(:handle_message, message)
      end
    end

    private

    def with_env(env_vars)
      original_values = {}
      env_vars.each do |key, value|
        original_values[key] = ENV[key]
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end

      yield
    ensure
      original_values.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
    end
  end
end
