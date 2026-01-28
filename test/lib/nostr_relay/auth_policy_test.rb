# frozen_string_literal: true

require "test_helper"

module NostrRelay
  class AuthPolicyTest < ActiveSupport::TestCase
    include NostrTestHelpers

    setup do
      @connection = MockConnection.new
      @pubkey = unique_hex(64)
      @original_relay_info = Rails.application.config.relay_info.dup
    end

    teardown do
      Rails.application.config.relay_info = @original_relay_info
      NostrRelay::Config.relay_info = @original_relay_info
    end

    def regular_event(pubkey: @pubkey)
      {
        "id" => unique_hex(64),
        "pubkey" => pubkey,
        "created_at" => Time.now.to_i,
        "kind" => 1,
        "tags" => [],
        "content" => "test",
        "sig" => unique_hex(128)
      }
    end

    def protected_event(pubkey: @pubkey)
      regular_event(pubkey:).merge(
        "tags" => [ [ "-" ] ]
      )
    end

    # =======================================================================
    # protected_event? Detection
    # =======================================================================

    test "detects protected event with dash tag" do
      event = protected_event
      assert AuthPolicy.protected_event?(event)
    end

    test "does not detect regular event as protected" do
      event = regular_event
      assert_not AuthPolicy.protected_event?(event)
    end

    test "handles symbol keys for tags" do
      event = { tags: [ [ "-" ] ] }
      assert AuthPolicy.protected_event?(event)
    end

    test "handles nil tags" do
      event = { "kind" => 1 }
      assert_not AuthPolicy.protected_event?(event)
    end

    # =======================================================================
    # event_requires_auth? - Global Auth Requirement
    # =======================================================================

    test "requires auth when auth_required is true" do
      update_config(auth_required: true, relay_url: "wss://test.relay.com")

      event = regular_event
      assert AuthPolicy.event_requires_auth?(event, @connection)
    end

    test "does not require auth for regular events when auth_required is false" do
      update_config(auth_required: false, relay_url: nil)

      event = regular_event
      assert_not AuthPolicy.event_requires_auth?(event, @connection)
    end

    # =======================================================================
    # event_requires_auth? - NIP-70 Protected Events
    # =======================================================================

    test "requires auth for protected events when auth disabled" do
      update_config(auth_required: false, relay_url: nil)

      event = protected_event
      assert AuthPolicy.event_requires_auth?(event, @connection)
    end

    test "requires auth for protected events when auth enabled but not authenticated" do
      update_config(auth_required: false, relay_url: "wss://test.relay.com")

      event = protected_event
      assert AuthPolicy.event_requires_auth?(event, @connection)
    end

    test "requires auth for protected events when authenticated with wrong pubkey" do
      update_config(auth_required: false, relay_url: "wss://test.relay.com")
      @connection.add_authenticated_pubkey(unique_hex(64)) # Different pubkey

      event = protected_event
      assert AuthPolicy.event_requires_auth?(event, @connection)
    end

    test "does not require auth for protected events when authenticated as author" do
      update_config(auth_required: false, relay_url: "wss://test.relay.com")
      @connection.add_authenticated_pubkey(@pubkey)

      event = protected_event(pubkey: @pubkey)
      assert_not AuthPolicy.event_requires_auth?(event, @connection)
    end

    # =======================================================================
    # author_authenticated?
    # =======================================================================

    test "author_authenticated returns true when pubkey is authenticated" do
      @connection.add_authenticated_pubkey(@pubkey)
      event = regular_event(pubkey: @pubkey)

      assert AuthPolicy.author_authenticated?(event, @connection)
    end

    test "author_authenticated returns false when pubkey is not authenticated" do
      event = regular_event(pubkey: @pubkey)
      assert_not AuthPolicy.author_authenticated?(event, @connection)
    end

    test "author_authenticated handles symbol keys" do
      @connection.add_authenticated_pubkey(@pubkey)
      event = { pubkey: @pubkey }

      assert AuthPolicy.author_authenticated?(event, @connection)
    end

    # =======================================================================
    # auth_error_message
    # =======================================================================

    test "returns auth-required message for regular events" do
      event = regular_event
      message = AuthPolicy.auth_error_message(event, @connection)

      assert_includes message, "auth-required:"
    end

    test "returns auth-required message for protected events when not authenticated" do
      event = protected_event
      message = AuthPolicy.auth_error_message(event, @connection)

      assert_includes message, "auth-required:"
      assert_includes message, "author"
    end

    test "returns restricted message for protected events when authenticated with wrong pubkey" do
      @connection.add_authenticated_pubkey(unique_hex(64)) # Different pubkey
      event = protected_event

      message = AuthPolicy.auth_error_message(event, @connection)

      assert_includes message, "restricted:"
      assert_includes message, "author"
    end

    private

    def update_config(auth_required:, relay_url:)
      config = Rails.application.config.relay_info.deep_dup
      config[:limitation] ||= {}
      config[:limitation][:auth_required] = auth_required
      config[:relay_url] = relay_url
      Rails.application.config.relay_info = config
      NostrRelay::Config.relay_info = config
    end
  end
end
