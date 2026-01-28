# frozen_string_literal: true

require "test_helper"

module NostrRelay
  module Handlers
    class AuthTest < ActiveSupport::TestCase
      include NostrTestHelpers

      setup do
        @connection = MockConnection.new
        @connection.challenge = "test_challenge_#{SecureRandom.hex(16)}"
        @relay_url = "wss://test.relay.com"
        @pubkey = unique_hex(64)
      end

      def valid_auth_payload
        {
          "id" => unique_hex(64),
          "pubkey" => @pubkey,
          "created_at" => Time.now.to_i,
          "kind" => Events::Kinds::AUTH,
          "tags" => [
            [ "relay", @relay_url ],
            [ "challenge", @connection.challenge ]
          ],
          "content" => "",
          "sig" => unique_hex(128)
        }
      end

      # =======================================================================
      # Challenge Verification
      # =======================================================================

      test "rejects AUTH when no challenge was issued" do
        @connection.challenge = nil
        payload = valid_auth_payload

        Auth.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_equal payload["id"], @connection.last_sent[1]
        assert_not @connection.last_sent[2]
        assert_includes @connection.last_sent[3], "no challenge"
      end

      # =======================================================================
      # Validation Flow (without stubbing - tests actual validation path)
      # =======================================================================

      test "rejects AUTH with invalid signature" do
        # A real invalid event will fail signature verification
        payload = valid_auth_payload

        Auth.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_not @connection.last_sent[2]  # success = false
        assert_not @connection.authenticated?
      end

      test "includes event_id in response for invalid events" do
        payload = valid_auth_payload

        Auth.call(connection: @connection, payload:)

        assert_equal "OK", @connection.last_sent[0]
        assert_equal payload["id"], @connection.last_sent[1]
      end

      # =======================================================================
      # Event ID Extraction
      # =======================================================================

      test "extracts event_id from payload" do
        payload = { "id" => "abc123" }
        assert_equal "abc123", Auth.extract_event_id(payload)
      end

      test "returns empty string for nil payload" do
        assert_equal "", Auth.extract_event_id(nil)
      end

      test "returns empty string for non-hash payload" do
        assert_equal "", Auth.extract_event_id("not a hash")
      end

      test "returns empty string for hash without id" do
        assert_equal "", Auth.extract_event_id({})
      end

      test "converts id to string" do
        assert_equal "123", Auth.extract_event_id({ "id" => 123 })
      end
    end
  end
end
