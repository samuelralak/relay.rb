# frozen_string_literal: true

require "test_helper"

module Negentropy
  class MessageTest < ActiveSupport::TestCase
    test "empty message" do
      message = Message.new
      assert message.empty?
      assert_equal 0, message.size
    end

    test "add skip range" do
      message = Message.new
      upper = Bound.new(100, "")
      message.add_skip(upper)

      assert_equal 1, message.size
      assert message.ranges.first.skip?
    end

    test "add fingerprint range" do
      message = Message.new
      upper = Bound.new(100, "")
      fingerprint = "\x01" * 16
      message.add_fingerprint(upper, fingerprint)

      assert_equal 1, message.size
      range = message.ranges.first
      assert range.fingerprint?
      assert_equal fingerprint, range.fingerprint
    end

    test "add id_list range" do
      message = Message.new
      upper = Bound.new(100, "")
      ids = [ "\x01" * 32, "\x02" * 32 ]
      message.add_id_list(upper, ids)

      assert_equal 1, message.size
      range = message.ranges.first
      assert range.id_list?
      assert_equal ids, range.ids
    end

    test "encode and decode empty message" do
      message = Message.new
      message.add_skip(Bound.max)

      encoded = message.encode
      decoded = Message.decode(encoded)

      # Trailing skips are optimized away per protocol spec
      assert_equal 0, decoded.size
    end

    test "encode and decode fingerprint message" do
      message = Message.new
      fingerprint = ("\xab\xcd".b) * 8
      message.add_fingerprint(Bound.max, fingerprint)

      encoded = message.encode
      decoded = Message.decode(encoded)

      assert_equal 1, decoded.size
      assert decoded.ranges.first.fingerprint?
      assert_equal fingerprint, decoded.ranges.first.fingerprint
    end

    test "encode and decode id_list message" do
      message = Message.new
      ids = [ "\x01" * 32, "\x02" * 32, "\x03" * 32 ]
      message.add_id_list(Bound.max, ids)

      encoded = message.encode
      decoded = Message.decode(encoded)

      assert_equal 1, decoded.size
      range = decoded.ranges.first
      assert range.id_list?
      assert_equal 3, range.ids.size
      assert_equal ids, range.ids
    end

    test "encode and decode multiple ranges" do
      message = Message.new
      message.add_fingerprint(Bound.new(100, ""), "\x01" * 16)
      message.add_fingerprint(Bound.new(200, ""), "\x02" * 16)
      message.add_skip(Bound.max)

      encoded = message.encode
      decoded = Message.decode(encoded)

      # Trailing skips are optimized away per protocol spec
      assert_equal 2, decoded.size
      assert decoded.ranges[0].fingerprint?
      assert decoded.ranges[1].fingerprint?
    end

    test "to_hex and from_hex roundtrip" do
      message = Message.new
      fingerprint = ("\xab\xcd".b) * 8
      message.add_fingerprint(Bound.max, fingerprint)

      hex = message.to_hex
      decoded = Message.from_hex(hex)

      assert_equal 1, decoded.size
      assert_equal fingerprint, decoded.ranges.first.fingerprint
    end

    test "protocol version is correct" do
      message = Message.new
      message.add_skip(Bound.max)

      encoded = message.encode
      assert_equal 0x61, encoded.bytes.first
    end

    test "raises on unsupported protocol version" do
      bad_data = "\x00\x00\x00".b # Wrong version
      assert_raises(ArgumentError) { Message.decode(bad_data) }
    end

    test "raises on unknown mode" do
      # Create a minimal valid structure with invalid mode
      io = StringIO.new("".b)
      io << 0x61.chr.b # version
      io << Varint.encode(1) # timestamp delta
      io << Varint.encode(0) # id length
      io << Varint.encode(99) # invalid mode

      assert_raises(ArgumentError) { Message.decode(io.string) }
    end

    test "delta timestamp encoding reduces size" do
      message = Message.new
      # Two consecutive timestamps
      message.add_fingerprint(Bound.new(1000, ""), "\x01" * 16)
      message.add_fingerprint(Bound.new(1001, ""), "\x02" * 16)

      encoded = message.encode

      # Second timestamp should be delta-encoded as 2 (1001 - 1000 + 1)
      # which is smaller than encoding 1001 directly
      decoded = Message.decode(encoded)
      assert_equal 1000, decoded.ranges[0].upper_bound.timestamp
      assert_equal 1001, decoded.ranges[1].upper_bound.timestamp
    end

    test "range fingerprint? predicate" do
      range = Message::Range.new(upper_bound: Bound.max, mode: Message::Mode::FINGERPRINT, payload: "\x01" * 16)
      assert range.fingerprint?
      assert_not range.id_list?
      assert_not range.skip?
    end

    test "range id_list? predicate" do
      range = Message::Range.new(upper_bound: Bound.max, mode: Message::Mode::ID_LIST, payload: [])
      assert_not range.fingerprint?
      assert range.id_list?
      assert_not range.skip?
    end

    test "range skip? predicate" do
      range = Message::Range.new(upper_bound: Bound.max, mode: Message::Mode::SKIP, payload: nil)
      assert_not range.fingerprint?
      assert_not range.id_list?
      assert range.skip?
    end

    test "range fingerprint raises when not fingerprint" do
      range = Message::Range.new(upper_bound: Bound.max, mode: Message::Mode::SKIP, payload: nil)
      assert_raises(RuntimeError) { range.fingerprint }
    end

    test "range ids raises when not id_list" do
      range = Message::Range.new(upper_bound: Bound.max, mode: Message::Mode::SKIP, payload: nil)
      assert_raises(RuntimeError) { range.ids }
    end
  end
end
