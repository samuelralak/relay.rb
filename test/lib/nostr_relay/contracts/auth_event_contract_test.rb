# frozen_string_literal: true

require "test_helper"

module NostrRelay
  module Contracts
    class AuthEventContractTest < ActiveSupport::TestCase
      include NostrTestHelpers

      def valid_auth_event
        {
          "id" => unique_hex(64),
          "pubkey" => unique_hex(64),
          "created_at" => Time.now.to_i,
          "kind" => Events::Kinds::AUTH,
          "tags" => [
            [ "relay", "wss://test.relay.com" ],
            [ "challenge", "test_challenge_123" ]
          ],
          "content" => "",
          "sig" => unique_hex(128)
        }
      end

      # =======================================================================
      # Valid Events
      # =======================================================================

      test "accepts valid auth event" do
        result = AuthEventContract.new.call(valid_auth_event)
        assert result.success?, "Expected success, got errors: #{result.errors.to_h}"
      end

      # =======================================================================
      # Required Fields
      # =======================================================================

      test "requires id" do
        event = valid_auth_event.except("id")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:id].present?
      end

      test "requires pubkey" do
        event = valid_auth_event.except("pubkey")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:pubkey].present?
      end

      test "requires created_at" do
        event = valid_auth_event.except("created_at")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:created_at].present?
      end

      test "requires kind" do
        event = valid_auth_event.except("kind")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:kind].present?
      end

      test "requires sig" do
        event = valid_auth_event.except("sig")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:sig].present?
      end

      # =======================================================================
      # Kind Validation
      # =======================================================================

      test "requires kind to be 22242" do
        event = valid_auth_event.merge("kind" => 1)
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:kind].present?
      end

      # =======================================================================
      # Tag Validation
      # =======================================================================

      test "requires relay tag" do
        event = valid_auth_event.merge(
          "tags" => [ [ "challenge", "test_challenge_123" ] ]
        )
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:tags].present?
      end

      test "requires challenge tag" do
        event = valid_auth_event.merge(
          "tags" => [ [ "relay", "wss://test.relay.com" ] ]
        )
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:tags].present?
      end

      # =======================================================================
      # Content Validation
      # =======================================================================

      test "requires content to be empty string" do
        event = valid_auth_event.merge("content" => "not empty")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:content].present?
      end

      # =======================================================================
      # Hex Field Validation
      # =======================================================================

      test "requires id to be 64-char hex" do
        event = valid_auth_event.merge("id" => "not-hex")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:id].present?
      end

      test "requires pubkey to be 64-char hex" do
        event = valid_auth_event.merge("pubkey" => "short")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:pubkey].present?
      end

      test "requires sig to be 128-char hex" do
        event = valid_auth_event.merge("sig" => "short")
        result = AuthEventContract.new.call(event)

        assert result.failure?
        assert result.errors.to_h[:sig].present?
      end
    end
  end
end
