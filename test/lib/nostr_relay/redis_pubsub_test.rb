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
