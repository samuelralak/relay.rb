# frozen_string_literal: true

require "test_helper"

module Search
  module Actions
    class ConvertNpubTest < ActiveSupport::TestCase
      # Test hex pubkey from a known npub
      # npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6
      # -> 3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d
      KNOWN_NPUB = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"
      KNOWN_HEX = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"

      test "converts valid npub to hex pubkey" do
        result = ConvertNpub.call(identifier: KNOWN_NPUB)

        assert result.success?
        assert_equal KNOWN_HEX, result.value![:pubkey]
      end

      test "converts uppercase npub to hex pubkey" do
        result = ConvertNpub.call(identifier: KNOWN_NPUB.upcase)

        assert result.success?
        assert_equal KNOWN_HEX, result.value![:pubkey]
      end

      test "accepts valid hex pubkey" do
        result = ConvertNpub.call(identifier: KNOWN_HEX)

        assert result.success?
        assert_equal KNOWN_HEX, result.value![:pubkey]
      end

      test "accepts uppercase hex pubkey and normalizes to lowercase" do
        result = ConvertNpub.call(identifier: KNOWN_HEX.upcase)

        assert result.success?
        assert_equal KNOWN_HEX, result.value![:pubkey]
      end

      test "fails for invalid npub" do
        result = ConvertNpub.call(identifier: "npub1invalid")

        assert result.failure?
        assert_equal :invalid_pubkey, result.failure
      end

      test "fails for invalid hex (wrong length)" do
        result = ConvertNpub.call(identifier: "3bf0c63fcb93463407af97a5e5ee64fa")

        assert result.failure?
        assert_equal :invalid_pubkey, result.failure
      end

      test "fails for invalid hex (non-hex characters)" do
        result = ConvertNpub.call(identifier: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")

        assert result.failure?
        assert_equal :invalid_pubkey, result.failure
      end

      test "fails for empty identifier" do
        result = ConvertNpub.call(identifier: "")

        assert result.failure?
        assert_equal :empty_identifier, result.failure
      end

      test "fails for random string" do
        result = ConvertNpub.call(identifier: "hello world")

        assert result.failure?
        assert_equal :invalid_pubkey, result.failure
      end
    end
  end
end
