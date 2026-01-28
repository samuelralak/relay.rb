# frozen_string_literal: true

require "test_helper"

module Auth
  class ValidateAuthEventTest < ActiveSupport::TestCase
    include NostrTestHelpers

    setup do
      @challenge = SecureRandom.hex(32)
      @relay_url = "wss://test.relay.com"
      @pubkey = unique_hex(64)
    end

    def valid_auth_event
      {
        "id" => unique_hex(64),
        "pubkey" => @pubkey,
        "created_at" => Time.now.to_i,
        "kind" => Events::Kinds::AUTH,
        "tags" => [
          [ "relay", @relay_url ],
          [ "challenge", @challenge ]
        ],
        "content" => "",
        "sig" => unique_hex(128)
      }
    end

    # =======================================================================
    # Contract Validation
    # =======================================================================

    test "fails for missing required fields" do
      result = ValidateAuthEvent.call(
        event_data: { "kind" => Events::Kinds::AUTH },
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
    end

    test "fails for event without id" do
      event = valid_auth_event.except("id")

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
    end

    # =======================================================================
    # Kind Verification
    # =======================================================================

    test "fails for wrong kind" do
      event = valid_auth_event.merge("kind" => 1)

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "22242"
    end

    # =======================================================================
    # Timestamp Verification
    # =======================================================================

    test "fails for timestamp too old" do
      event = valid_auth_event.merge("created_at" => Time.now.to_i - 700)

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "timestamp too old"
    end

    test "fails for timestamp too far in future" do
      event = valid_auth_event.merge("created_at" => Time.now.to_i + 700)

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "timestamp too far in future"
    end

    test "accepts timestamp within valid range" do
      event = valid_auth_event.merge("created_at" => Time.now.to_i - 300)

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      # May fail on signature but not on timestamp
      if result.failure?
        assert_not_includes result.failure[1], "timestamp"
      end
    end

    # =======================================================================
    # Challenge Tag Verification
    # =======================================================================

    test "fails for missing challenge tag" do
      event = valid_auth_event.merge("tags" => [ [ "relay", @relay_url ] ])

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "challenge"
    end

    test "fails for challenge mismatch" do
      event = valid_auth_event.merge(
        "tags" => [
          [ "relay", @relay_url ],
          [ "challenge", "wrong_challenge" ]
        ]
      )

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "challenge mismatch"
    end

    # =======================================================================
    # Relay URL Tag Verification
    # =======================================================================

    test "fails for missing relay tag" do
      event = valid_auth_event.merge("tags" => [ [ "challenge", @challenge ] ])

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "relay"
    end

    test "fails for relay URL mismatch" do
      event = valid_auth_event.merge(
        "tags" => [
          [ "relay", "wss://wrong.relay.com" ],
          [ "challenge", @challenge ]
        ]
      )

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "relay URL mismatch"
    end

    test "normalizes relay URLs for comparison (case insensitive)" do
      event = valid_auth_event.merge(
        "tags" => [
          [ "relay", "WSS://TEST.RELAY.COM" ],
          [ "challenge", @challenge ]
        ]
      )

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      # Should fail on ID/signature, not relay URL
      if result.failure?
        assert_not_includes result.failure[1], "relay URL mismatch"
      end
    end

    test "normalizes relay URLs for comparison (trailing slash)" do
      event = valid_auth_event.merge(
        "tags" => [
          [ "relay", "wss://test.relay.com/" ],
          [ "challenge", @challenge ]
        ]
      )

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      # Should fail on ID/signature, not relay URL
      if result.failure?
        assert_not_includes result.failure[1], "relay URL mismatch"
      end
    end

    # =======================================================================
    # ID and Signature Verification
    # =======================================================================

    test "fails for invalid event ID" do
      event = valid_auth_event.merge("id" => "0" * 64)  # Wrong ID

      result = ValidateAuthEvent.call(
        event_data: event,
        connection_challenge: @challenge,
        relay_url: @relay_url
      )

      assert result.failure?
      assert_equal :invalid, result.failure[0]
      assert_includes result.failure[1], "event id"
    end
  end
end
