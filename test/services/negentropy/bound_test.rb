# frozen_string_literal: true

require "test_helper"

module Negentropy
  class BoundTest < ActiveSupport::TestCase
    test "min bound" do
      bound = Bound.min
      assert bound.min?
      assert_equal 0, bound.timestamp
      assert_equal "", bound.id
    end

    test "max bound" do
      bound = Bound.max
      assert bound.infinity?
      assert_equal Bound::INFINITY_TIMESTAMP, bound.timestamp
      assert_equal "\xFF".b * 32, bound.id
    end

    test "from_event with hash" do
      event = { id: "a" * 64, created_at: 1000 }
      bound = Bound.from_event(event)

      assert_equal 1000, bound.timestamp
      assert_equal [ "a" * 64 ].pack("H*"), bound.id
      assert_equal "a" * 64, bound.id_hex
    end

    test "comparison by timestamp" do
      bound1 = Bound.new(100, "")
      bound2 = Bound.new(200, "")

      assert bound1 < bound2
      assert bound2 > bound1
    end

    test "comparison by id when timestamps equal" do
      id1 = "\x01" * 32
      id2 = "\x02" * 32

      bound1 = Bound.new(100, id1)
      bound2 = Bound.new(100, id2)

      assert bound1 < bound2
    end

    test "equality" do
      id = "\x01" * 32
      bound1 = Bound.new(100, id)
      bound2 = Bound.new(100, id)

      assert_equal bound1, bound2
      assert bound1.eql?(bound2)
    end

    test "encode and decode min bound" do
      bound = Bound.min
      encoded = bound.encode

      io = StringIO.new(encoded)
      decoded = Bound.decode(io)

      assert decoded.min?
      assert_equal bound, decoded
    end

    test "encode and decode max bound" do
      bound = Bound.max
      encoded = bound.encode

      io = StringIO.new(encoded)
      decoded = Bound.decode(io)

      assert decoded.infinity?
    end

    test "encode and decode regular bound" do
      id = ("\xab\xcd".b) * 16
      bound = Bound.new(12345, id)
      encoded = bound.encode

      io = StringIO.new(encoded)
      decoded = Bound.decode(io)

      assert_equal 12345, decoded.timestamp
      assert_equal id.b, decoded.id
    end

    test "encode and decode with delta timestamp" do
      id = "\x01" * 32
      bound = Bound.new(1000, id)
      prev_timestamp = 500

      encoded = bound.encode(prev_timestamp)
      io = StringIO.new(encoded)
      decoded = Bound.decode(io, prev_timestamp)

      assert_equal 1000, decoded.timestamp
      assert_equal id, decoded.id
    end

    test "id_hex returns hex representation" do
      hex_id = "ab" * 32
      binary_id = [ hex_id ].pack("H*")
      bound = Bound.new(100, binary_id)

      assert_equal hex_id, bound.id_hex
    end

    test "to_s for min bound" do
      assert_equal "Bound(min)", Bound.min.to_s
    end

    test "to_s for max bound" do
      assert_equal "Bound(infinity)", Bound.max.to_s
    end

    test "to_s for regular bound" do
      id = "\xab" * 32
      bound = Bound.new(100, id)
      assert_match(/Bound\(100, abababab/, bound.to_s)
    end

    test "hash is consistent for equal bounds" do
      id = "\x01" * 32
      bound1 = Bound.new(100, id)
      bound2 = Bound.new(100, id)

      assert_equal bound1.hash, bound2.hash
    end

    test "comparison returns nil for non-Bound" do
      bound = Bound.new(100, "")
      assert_nil bound <=> "not a bound"
    end
  end
end
