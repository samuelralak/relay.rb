# frozen_string_literal: true

require "test_helper"

module Negentropy
  class VarintTest < ActiveSupport::TestCase
    test "encodes zero" do
      assert_equal "\x00".b, Varint.encode(0)
    end

    test "encodes small values" do
      assert_equal "\x01".b, Varint.encode(1)
      assert_equal "\x7F".b, Varint.encode(127)
    end

    test "encodes values requiring two bytes" do
      # 128 = 0x80 0x01 in MSB-first varint
      assert_equal "\x81\x00".b, Varint.encode(128)
      # 16383 = 0xFF 0x7F
      assert_equal "\xFF\x7F".b, Varint.encode(16383)
    end

    test "encodes large values" do
      # 16384 = 0x81 0x80 0x00
      assert_equal "\x81\x80\x00".b, Varint.encode(16384)
    end

    test "decodes zero" do
      value, bytes_consumed = Varint.decode("\x00".b)
      assert_equal 0, value
      assert_equal 1, bytes_consumed
    end

    test "decodes small values" do
      value, bytes_consumed = Varint.decode("\x01".b)
      assert_equal 1, value
      assert_equal 1, bytes_consumed

      value, bytes_consumed = Varint.decode("\x7F".b)
      assert_equal 127, value
      assert_equal 1, bytes_consumed
    end

    test "decodes values requiring two bytes" do
      value, bytes_consumed = Varint.decode("\x81\x00".b)
      assert_equal 128, value
      assert_equal 2, bytes_consumed
    end

    test "decodes with offset" do
      data = "\x00\x01\x02".b
      value, bytes_consumed = Varint.decode(data, 1)
      assert_equal 1, value
      assert_equal 1, bytes_consumed
    end

    test "decode from IO" do
      io = StringIO.new("\x81\x00".b)
      value = Varint.decode_from_io(io)
      assert_equal 128, value
    end

    test "roundtrip encoding" do
      [ 0, 1, 127, 128, 255, 16383, 16384, 100_000, 1_000_000 ].each do |n|
        encoded = Varint.encode(n)
        decoded, = Varint.decode(encoded)
        assert_equal n, decoded, "Roundtrip failed for #{n}"
      end
    end

    test "raises on negative values" do
      assert_raises(ArgumentError) { Varint.encode(-1) }
    end

    test "raises on unexpected end of data" do
      assert_raises(ArgumentError) { Varint.decode("\x81".b) }
    end
  end
end
