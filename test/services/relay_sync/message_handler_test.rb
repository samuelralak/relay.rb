# frozen_string_literal: true

require "test_helper"

module RelaySync
  class MessageHandlerTest < ActiveSupport::TestCase
    # Parsing tests
    test "parses EVENT message" do
      event = { "id" => "abc", "pubkey" => "xyz", "kind" => 1 }
      raw = JSON.generate([ "EVENT", "sub123", event ])

      result = MessageHandler.parse(raw)

      assert_equal :event, result[:type]
      assert_equal "sub123", result[:subscription_id]
      assert_equal event, result[:event]
    end

    test "parses EOSE message" do
      raw = JSON.generate([ "EOSE", "sub123" ])

      result = MessageHandler.parse(raw)

      assert_equal :eose, result[:type]
      assert_equal "sub123", result[:subscription_id]
    end

    test "parses OK message with success" do
      raw = JSON.generate([ "OK", "event_id_123", true, "" ])

      result = MessageHandler.parse(raw)

      assert_equal :ok, result[:type]
      assert_equal "event_id_123", result[:event_id]
      assert result[:success]
      assert_equal "", result[:message]
    end

    test "parses OK message with failure" do
      raw = JSON.generate([ "OK", "event_id_123", false, "duplicate: already exists" ])

      result = MessageHandler.parse(raw)

      assert_equal :ok, result[:type]
      assert_equal "event_id_123", result[:event_id]
      assert_not result[:success]
      assert_equal "duplicate: already exists", result[:message]
    end

    test "parses NOTICE message" do
      raw = JSON.generate([ "NOTICE", "Rate limited" ])

      result = MessageHandler.parse(raw)

      assert_equal :notice, result[:type]
      assert_equal "Rate limited", result[:message]
    end

    test "parses NEG-MSG message" do
      raw = JSON.generate([ "NEG-MSG", "sub123", "abcd1234" ])

      result = MessageHandler.parse(raw)

      assert_equal :neg_msg, result[:type]
      assert_equal "sub123", result[:subscription_id]
      assert_equal "abcd1234", result[:message]
    end

    test "parses NEG-ERR message" do
      raw = JSON.generate([ "NEG-ERR", "sub123", "RESULTS_TOO_BIG" ])

      result = MessageHandler.parse(raw)

      assert_equal :neg_err, result[:type]
      assert_equal "sub123", result[:subscription_id]
      assert_equal "RESULTS_TOO_BIG", result[:error]
    end

    test "parses CLOSED message" do
      raw = JSON.generate([ "CLOSED", "sub123", "subscription replaced" ])

      result = MessageHandler.parse(raw)

      assert_equal :closed, result[:type]
      assert_equal "sub123", result[:subscription_id]
      assert_equal "subscription replaced", result[:message]
    end

    test "parses AUTH message" do
      raw = JSON.generate([ "AUTH", "challenge123" ])

      result = MessageHandler.parse(raw)

      assert_equal :auth, result[:type]
      assert_equal "challenge123", result[:challenge]
    end

    test "returns unknown for unrecognized message type" do
      raw = JSON.generate([ "UNKNOWN_TYPE", "data" ])

      result = MessageHandler.parse(raw)

      assert_equal :unknown, result[:type]
      assert_equal [ "UNKNOWN_TYPE", "data" ], result[:raw]
    end

    test "returns error for invalid JSON" do
      result = MessageHandler.parse("not json")

      assert_equal :error, result[:type]
      assert_match(/Invalid JSON/, result[:message])
    end

    # Message building tests
    test "build_req creates REQ message" do
      filters = [ { kinds: [ 1 ] }, { authors: [ "abc" ] } ]
      result = MessageHandler.build_req("sub123", *filters)

      assert_equal [ "REQ", "sub123", { kinds: [ 1 ] }, { authors: [ "abc" ] } ], result
    end

    test "build_close creates CLOSE message" do
      result = MessageHandler.build_close("sub123")

      assert_equal [ "CLOSE", "sub123" ], result
    end

    test "build_event creates EVENT message" do
      event = { id: "abc", pubkey: "xyz" }
      result = MessageHandler.build_event(event)

      assert_equal [ "EVENT", { id: "abc", pubkey: "xyz" } ], result
    end

    test "build_neg_open creates NEG-OPEN message" do
      filter = { kinds: [ 1 ] }
      result = MessageHandler.build_neg_open("sub123", filter, "initial_msg")

      assert_equal [ "NEG-OPEN", "sub123", { kinds: [ 1 ] }, "initial_msg" ], result
    end

    test "build_neg_msg creates NEG-MSG message" do
      result = MessageHandler.build_neg_msg("sub123", "response_msg")

      assert_equal [ "NEG-MSG", "sub123", "response_msg" ], result
    end

    test "build_neg_close creates NEG-CLOSE message" do
      result = MessageHandler.build_neg_close("sub123")

      assert_equal [ "NEG-CLOSE", "sub123" ], result
    end

    # Event validation tests
    test "valid_event? returns true for valid event with string keys" do
      event = {
        "id" => "a" * 64,
        "pubkey" => "b" * 64,
        "created_at" => 1234567890,
        "kind" => 1,
        "tags" => [],
        "content" => "hello",
        "sig" => "c" * 128
      }

      assert MessageHandler.valid_event?(event)
    end

    test "valid_event? returns true for valid event with symbol keys" do
      event = {
        id: "a" * 64,
        pubkey: "b" * 64,
        created_at: 1234567890,
        kind: 1,
        tags: [],
        content: "hello",
        sig: "c" * 128
      }

      assert MessageHandler.valid_event?(event)
    end

    test "valid_event? returns false for missing required key" do
      event = {
        "id" => "a" * 64,
        "pubkey" => "b" * 64,
        "created_at" => 1234567890,
        "kind" => 1,
        "tags" => [],
        "content" => "hello"
        # missing sig
      }

      assert_not MessageHandler.valid_event?(event)
    end

    test "valid_event? returns false for non-hash" do
      assert_not MessageHandler.valid_event?("not a hash")
      assert_not MessageHandler.valid_event?(nil)
      assert_not MessageHandler.valid_event?([])
    end
  end
end
