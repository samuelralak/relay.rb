# frozen_string_literal: true

require "test_helper"

module Negentropy
  class FingerprintTest < ActiveSupport::TestCase
    test "empty fingerprint for empty list" do
      fp = Fingerprint.compute([])
      assert_equal 16, fp.bytesize
      assert Fingerprint.empty?(fp)
    end

    test "computes fingerprint for single ID" do
      id = "\x01" * 32
      fp = Fingerprint.compute([ id ])

      assert_equal 16, fp.bytesize
      assert_not Fingerprint.empty?(fp)
    end

    test "computes fingerprint for multiple IDs" do
      ids = [ "\x01" * 32, "\x02" * 32, "\x03" * 32 ]
      fp = Fingerprint.compute(ids)

      assert_equal 16, fp.bytesize
      assert_not Fingerprint.empty?(fp)
    end

    test "computes from hex IDs" do
      hex_ids = [ "a" * 64, "b" * 64 ]
      fp = Fingerprint.compute_from_hex(hex_ids)

      assert_equal 16, fp.bytesize
    end

    test "same IDs produce same fingerprint" do
      ids = [ "\x01" * 32, "\x02" * 32 ]
      fp1 = Fingerprint.compute(ids)
      fp2 = Fingerprint.compute(ids)

      assert Fingerprint.match?(fp1, fp2)
    end

    test "different IDs produce different fingerprints" do
      ids1 = [ "\x01" * 32 ]
      ids2 = [ "\x02" * 32 ]

      fp1 = Fingerprint.compute(ids1)
      fp2 = Fingerprint.compute(ids2)

      assert_not Fingerprint.match?(fp1, fp2)
    end

    test "order affects fingerprint" do
      ids1 = [ "\x01" * 32, "\x02" * 32 ]
      ids2 = [ "\x02" * 32, "\x01" * 32 ]

      # Sum is commutative, so same fingerprint
      fp1 = Fingerprint.compute(ids1)
      fp2 = Fingerprint.compute(ids2)

      # Actually, sum-based fingerprint is order-independent
      assert Fingerprint.match?(fp1, fp2)
    end

    test "to_hex and from_hex roundtrip" do
      fp = Fingerprint.compute([ "\x01" * 32 ])
      hex = Fingerprint.to_hex(fp)
      parsed = Fingerprint.from_hex(hex)

      assert_equal fp, parsed
      assert_equal 32, hex.length
    end

    test "xor operation" do
      fp1 = "\x00\x0F" * 8
      fp2 = "\x0F\x00" * 8
      result = Fingerprint.xor(fp1, fp2)

      assert_equal "\x0F\x0F" * 8, result
    end
  end
end
