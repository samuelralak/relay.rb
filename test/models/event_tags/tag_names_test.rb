# frozen_string_literal: true

require "test_helper"

module EventTags
  class TagNamesTest < ActiveSupport::TestCase
    # =========================================
    # Core Tag Constants Tests
    # =========================================

    test "core reference tags are defined" do
      assert_equal "e", TagNames::EVENT
      assert_equal "p", TagNames::PUBKEY
      assert_equal "a", TagNames::ADDRESSABLE
      assert_equal "d", TagNames::IDENTIFIER
    end

    test "content tags are defined" do
      assert_equal "t", TagNames::HASHTAG
      assert_equal "r", TagNames::REFERENCE
      assert_equal "g", TagNames::GEOHASH
      assert_equal "k", TagNames::KIND
    end

    test "NIP-22 root tags are uppercase" do
      assert_equal "E", TagNames::ROOT_EVENT
      assert_equal "A", TagNames::ROOT_ADDRESS
      assert_equal "I", TagNames::ROOT_IDENTITY
      assert_equal "P", TagNames::ROOT_PUBKEY
      assert_equal "K", TagNames::ROOT_SCOPE
    end

    test "label tags are defined" do
      assert_equal "l", TagNames::LABEL
      assert_equal "L", TagNames::LABEL_NAMESPACE
    end

    test "media tags are defined" do
      assert_equal "content-warning", TagNames::CONTENT_WARNING
      assert_equal "subject", TagNames::SUBJECT
      assert_equal "title", TagNames::TITLE
      assert_equal "summary", TagNames::SUMMARY
      assert_equal "image", TagNames::IMAGE
      assert_equal "imeta", TagNames::IMETA
    end

    test "protocol tags are defined" do
      assert_equal "expiration", TagNames::EXPIRATION
      assert_equal "nonce", TagNames::NONCE
      assert_equal "relay", TagNames::RELAY
      assert_equal "challenge", TagNames::CHALLENGE
      assert_equal "alt", TagNames::ALT
    end

    test "payment tags are defined" do
      assert_equal "amount", TagNames::AMOUNT
      assert_equal "bolt11", TagNames::BOLT11
      assert_equal "lnurl", TagNames::LNURL
      assert_equal "zap", TagNames::ZAP
    end

    # =========================================
    # INDEXABLE Set Tests
    # =========================================

    test "INDEXABLE contains all lowercase letters" do
      ("a".."z").each do |letter|
        assert_includes TagNames::INDEXABLE, letter,
                        "INDEXABLE should include lowercase '#{letter}'"
      end
    end

    test "INDEXABLE contains all uppercase letters" do
      ("A".."Z").each do |letter|
        assert_includes TagNames::INDEXABLE, letter,
                        "INDEXABLE should include uppercase '#{letter}'"
      end
    end

    test "INDEXABLE is frozen" do
      assert TagNames::INDEXABLE.frozen?
    end

    test "INDEXABLE has exactly 52 elements" do
      assert_equal 52, TagNames::INDEXABLE.size
    end

    test "INDEXABLE is a Set for O(1) lookup" do
      assert_instance_of Set, TagNames::INDEXABLE
    end

    # =========================================
    # indexable? Method Tests
    # =========================================

    test "indexable? returns true for lowercase single letters" do
      ("a".."z").each do |letter|
        assert TagNames.indexable?(letter),
               "indexable? should return true for '#{letter}'"
      end
    end

    test "indexable? returns true for uppercase single letters" do
      ("A".."Z").each do |letter|
        assert TagNames.indexable?(letter),
               "indexable? should return true for '#{letter}'"
      end
    end

    test "indexable? returns false for multi-character strings" do
      assert_not TagNames.indexable?("ab")
      assert_not TagNames.indexable?("content-warning")
      assert_not TagNames.indexable?("expiration")
    end

    test "indexable? returns false for empty string" do
      assert_not TagNames.indexable?("")
    end

    test "indexable? returns false for non-letter single characters" do
      assert_not TagNames.indexable?("1")
      assert_not TagNames.indexable?("@")
      assert_not TagNames.indexable?("#")
      assert_not TagNames.indexable?("-")
      assert_not TagNames.indexable?(" ")
    end

    test "indexable? returns false for nil" do
      assert_not TagNames.indexable?(nil)
    end

    test "indexable? returns false for non-string types" do
      assert_not TagNames.indexable?(1)
      assert_not TagNames.indexable?(:e)
      assert_not TagNames.indexable?([ "e" ])
    end

    # =========================================
    # Practical Usage Tests
    # =========================================

    test "common single-letter tags are indexable" do
      common_tags = %w[e p t a d r g k l L E A I P K]
      common_tags.each do |tag|
        assert TagNames.indexable?(tag),
               "Common tag '#{tag}' should be indexable"
      end
    end

    test "multi-character NIP tags are not indexable" do
      multi_char_tags = %w[expiration content-warning subject title summary image nonce relay alt]
      multi_char_tags.each do |tag|
        assert_not TagNames.indexable?(tag),
                   "Multi-char tag '#{tag}' should NOT be indexable"
      end
    end
  end
end
