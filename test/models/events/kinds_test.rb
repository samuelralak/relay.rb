# frozen_string_literal: true

require "test_helper"

module Events
  class KindsTest < ActiveSupport::TestCase
    # =========================================
    # Constant Tests
    # =========================================

    test "HEX_PATTERN validates lowercase hex" do
      assert_match Kinds::HEX_PATTERN, "0123456789abcdef"
      assert_no_match Kinds::HEX_PATTERN, "ABCDEF"
      assert_no_match Kinds::HEX_PATTERN, "ghijkl"
      assert_no_match Kinds::HEX_PATTERN, "abc-def"
    end

    test "core kind constants are defined" do
      assert_equal 0, Kinds::METADATA
      assert_equal 1, Kinds::TEXT_NOTE
      assert_equal 3, Kinds::FOLLOWS
      assert_equal 3, Kinds::CONTACTS
      assert_equal 5, Kinds::DELETION
      assert_equal 7, Kinds::REACTION
    end

    test "replaceable kind constants are defined" do
      assert_equal 10_000, Kinds::MUTE_LIST
      assert_equal 10_002, Kinds::RELAY_LIST
    end

    test "ephemeral kind constants are defined" do
      assert_equal 22_242, Kinds::AUTH
      assert_equal 24_133, Kinds::NOSTR_CONNECT
    end

    test "addressable kind constants are defined" do
      assert_equal 30_023, Kinds::LONG_FORM
      assert_equal 30_000, Kinds::FOLLOW_SETS
    end

    # =========================================
    # Range Tests
    # =========================================

    test "REGULAR_RANGE_PRIMARY covers 1000-9999" do
      assert Kinds::REGULAR_RANGE_PRIMARY.cover?(1000)
      assert Kinds::REGULAR_RANGE_PRIMARY.cover?(9999)
      assert_not Kinds::REGULAR_RANGE_PRIMARY.cover?(999)
      assert_not Kinds::REGULAR_RANGE_PRIMARY.cover?(10_000)
    end

    test "REGULAR_RANGE_LEGACY covers 4-44" do
      assert Kinds::REGULAR_RANGE_LEGACY.cover?(4)
      assert Kinds::REGULAR_RANGE_LEGACY.cover?(44)
      assert_not Kinds::REGULAR_RANGE_LEGACY.cover?(3)
      assert_not Kinds::REGULAR_RANGE_LEGACY.cover?(45)
    end

    test "REGULAR_STANDALONE includes 1 and 2" do
      assert_includes Kinds::REGULAR_STANDALONE, 1
      assert_includes Kinds::REGULAR_STANDALONE, 2
    end

    test "REPLACEABLE_RANGE covers 10000-19999" do
      assert Kinds::REPLACEABLE_RANGE.cover?(10_000)
      assert Kinds::REPLACEABLE_RANGE.cover?(19_999)
      assert_not Kinds::REPLACEABLE_RANGE.cover?(9999)
      assert_not Kinds::REPLACEABLE_RANGE.cover?(20_000)
    end

    test "REPLACEABLE_STANDALONE includes 0 and 3" do
      assert_includes Kinds::REPLACEABLE_STANDALONE, 0
      assert_includes Kinds::REPLACEABLE_STANDALONE, 3
    end

    test "EPHEMERAL_RANGE covers 20000-29999" do
      assert Kinds::EPHEMERAL_RANGE.cover?(20_000)
      assert Kinds::EPHEMERAL_RANGE.cover?(29_999)
      assert_not Kinds::EPHEMERAL_RANGE.cover?(19_999)
      assert_not Kinds::EPHEMERAL_RANGE.cover?(30_000)
    end

    test "ADDRESSABLE_RANGE covers 30000-39999" do
      assert Kinds::ADDRESSABLE_RANGE.cover?(30_000)
      assert Kinds::ADDRESSABLE_RANGE.cover?(39_999)
      assert_not Kinds::ADDRESSABLE_RANGE.cover?(29_999)
      assert_not Kinds::ADDRESSABLE_RANGE.cover?(40_000)
    end

    # =========================================
    # Classification Method Tests - regular?
    # =========================================

    test "regular? returns true for text notes (kind 1)" do
      assert Kinds.regular?(1)
    end

    test "regular? returns true for recommend relay (kind 2)" do
      assert Kinds.regular?(2)
    end

    test "regular? returns true for legacy range (4-44)" do
      assert Kinds.regular?(4)
      assert Kinds.regular?(7)   # reaction
      assert Kinds.regular?(40)  # channel create
      assert Kinds.regular?(44)
    end

    test "regular? returns true for primary range (1000-9999)" do
      assert Kinds.regular?(1000)
      assert Kinds.regular?(5000)  # job request
      assert Kinds.regular?(9735)  # zap
    end

    test "regular? returns false for non-regular kinds" do
      assert_not Kinds.regular?(0)     # metadata - replaceable
      assert_not Kinds.regular?(3)     # follows - replaceable
      assert_not Kinds.regular?(10_002) # relay list - replaceable
      assert_not Kinds.regular?(22_242) # auth - ephemeral
      assert_not Kinds.regular?(30_023) # long form - addressable
    end

    # =========================================
    # Classification Method Tests - replaceable?
    # =========================================

    test "replaceable? returns true for metadata (kind 0)" do
      assert Kinds.replaceable?(0)
    end

    test "replaceable? returns true for follows (kind 3)" do
      assert Kinds.replaceable?(3)
    end

    test "replaceable? returns true for replaceable range (10000-19999)" do
      assert Kinds.replaceable?(10_000)
      assert Kinds.replaceable?(10_002)  # relay list
      assert Kinds.replaceable?(19_999)
    end

    test "replaceable? returns false for non-replaceable kinds" do
      assert_not Kinds.replaceable?(1)     # text note
      assert_not Kinds.replaceable?(7)     # reaction
      assert_not Kinds.replaceable?(22_242) # auth
      assert_not Kinds.replaceable?(30_023) # long form
    end

    # =========================================
    # Classification Method Tests - ephemeral?
    # =========================================

    test "ephemeral? returns true for ephemeral range (20000-29999)" do
      assert Kinds.ephemeral?(20_000)
      assert Kinds.ephemeral?(22_242)  # auth
      assert Kinds.ephemeral?(24_133)  # nostr connect
      assert Kinds.ephemeral?(29_999)
    end

    test "ephemeral? returns false for non-ephemeral kinds" do
      assert_not Kinds.ephemeral?(1)
      assert_not Kinds.ephemeral?(0)
      assert_not Kinds.ephemeral?(10_002)
      assert_not Kinds.ephemeral?(30_023)
    end

    # =========================================
    # Classification Method Tests - addressable?
    # =========================================

    test "addressable? returns true for addressable range (30000-39999)" do
      assert Kinds.addressable?(30_000)  # follow sets
      assert Kinds.addressable?(30_023)  # long form
      assert Kinds.addressable?(39_999)
    end

    test "addressable? returns false for non-addressable kinds" do
      assert_not Kinds.addressable?(1)
      assert_not Kinds.addressable?(0)
      assert_not Kinds.addressable?(22_242)
      assert_not Kinds.addressable?(10_002)
    end

    test "parameterized_replaceable? is alias for addressable?" do
      assert_equal Kinds.addressable?(30_023), Kinds.parameterized_replaceable?(30_023)
      assert_equal Kinds.addressable?(1), Kinds.parameterized_replaceable?(1)
    end

    # =========================================
    # Utility Method Tests
    # =========================================

    test "storable? returns true for non-ephemeral kinds" do
      assert Kinds.storable?(1)       # regular
      assert Kinds.storable?(0)       # replaceable
      assert Kinds.storable?(30_023)  # addressable
    end

    test "storable? returns false for ephemeral kinds" do
      assert_not Kinds.storable?(22_242)  # auth
      assert_not Kinds.storable?(24_133)  # nostr connect
      assert_not Kinds.storable?(20_000)
    end

    test "classification returns :regular for regular kinds" do
      assert_equal :regular, Kinds.classification(1)
      assert_equal :regular, Kinds.classification(2)
      assert_equal :regular, Kinds.classification(7)
      assert_equal :regular, Kinds.classification(1000)
    end

    test "classification returns :replaceable for replaceable kinds" do
      assert_equal :replaceable, Kinds.classification(0)
      assert_equal :replaceable, Kinds.classification(3)
      assert_equal :replaceable, Kinds.classification(10_002)
    end

    test "classification returns :ephemeral for ephemeral kinds" do
      assert_equal :ephemeral, Kinds.classification(22_242)
      assert_equal :ephemeral, Kinds.classification(24_133)
    end

    test "classification returns :addressable for addressable kinds" do
      assert_equal :addressable, Kinds.classification(30_023)
      assert_equal :addressable, Kinds.classification(30_000)
    end

    # =========================================
    # Edge Case Tests
    # =========================================

    test "classification handles boundary kinds correctly" do
      # Exact boundaries
      assert_equal :regular, Kinds.classification(1000)
      assert_equal :regular, Kinds.classification(9999)
      assert_equal :replaceable, Kinds.classification(10_000)
      assert_equal :replaceable, Kinds.classification(19_999)
      assert_equal :ephemeral, Kinds.classification(20_000)
      assert_equal :ephemeral, Kinds.classification(29_999)
      assert_equal :addressable, Kinds.classification(30_000)
      assert_equal :addressable, Kinds.classification(39_999)
    end

    test "kinds above 40000 are classified as regular" do
      # Per NIP-01, kinds >= 40000 are regular
      assert_equal :regular, Kinds.classification(40_000)
      assert_equal :regular, Kinds.classification(65_535)
    end

    test "standalone kinds take precedence over ranges" do
      # Kind 0 is replaceable (standalone), not regular
      assert_not Kinds.regular?(0)
      assert Kinds.replaceable?(0)

      # Kind 3 is replaceable (standalone), not regular
      assert_not Kinds.regular?(3)
      assert Kinds.replaceable?(3)
    end
  end
end
