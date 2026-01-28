# frozen_string_literal: true

require "test_helper"

module Auth
  module Actions
    class NormalizeRelayUrlTest < ActiveSupport::TestCase
      test "lowercases URL" do
        result = NormalizeRelayUrl.call(url: "WSS://RELAY.EXAMPLE.COM")

        assert result.success?
        assert_equal "wss://relay.example.com", result.value![:normalized_url]
      end

      test "strips whitespace" do
        result = NormalizeRelayUrl.call(url: "  wss://relay.example.com  ")

        assert result.success?
        assert_equal "wss://relay.example.com", result.value![:normalized_url]
      end

      test "removes trailing slashes" do
        result = NormalizeRelayUrl.call(url: "wss://relay.example.com/")

        assert result.success?
        assert_equal "wss://relay.example.com", result.value![:normalized_url]
      end

      test "removes multiple trailing slashes" do
        result = NormalizeRelayUrl.call(url: "wss://relay.example.com///")

        assert result.success?
        assert_equal "wss://relay.example.com", result.value![:normalized_url]
      end

      test "preserves path without trailing slash" do
        result = NormalizeRelayUrl.call(url: "wss://relay.example.com/path")

        assert result.success?
        assert_equal "wss://relay.example.com/path", result.value![:normalized_url]
      end

      test "removes trailing slash from path" do
        result = NormalizeRelayUrl.call(url: "wss://relay.example.com/path/")

        assert result.success?
        assert_equal "wss://relay.example.com/path", result.value![:normalized_url]
      end

      test "fails for blank URL" do
        result = NormalizeRelayUrl.call(url: "")

        assert result.failure?
        assert_equal :invalid, result.failure[0]
      end

      test "fails for nil-like URL" do
        result = NormalizeRelayUrl.call(url: "   ")

        assert result.failure?
        assert_equal :invalid, result.failure[0]
      end
    end
  end
end
