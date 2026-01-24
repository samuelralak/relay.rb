# frozen_string_literal: true

module Negentropy
  # Represents a boundary point in the (timestamp, event_id) space
  # Used to define ranges for set reconciliation
  class Bound
    include Comparable

    INFINITY_TIMESTAMP = 2**64 - 1
    ID_SIZE = 32 # 256-bit event ID

    attr_reader :timestamp, :id

    # @param timestamp [Integer] Unix timestamp (0 to 2^64-1)
    # @param id [String] 32-byte binary event ID (can be empty for min bound)
    def initialize(timestamp, id = "")
      @timestamp = timestamp
      @id = id.b
    end

    # Create a minimum bound (start of all ranges)
    def self.min
      new(0, "")
    end

    # Create a maximum bound (end of all ranges)
    def self.max
      new(INFINITY_TIMESTAMP, "\xFF".b * ID_SIZE)
    end

    # Create a bound from an event
    # @param event [Object, Hash] event with created_at/nostr_created_at and id/event_id
    def self.from_event(event)
      timestamp = event.is_a?(Hash) ? event[:created_at] : event.nostr_created_at.to_i
      id = event.is_a?(Hash) ? event[:id] : event.event_id
      # Convert hex ID to binary
      binary_id = [ id ].pack("H*")
      new(timestamp, binary_id)
    end

    # Compare bounds for ordering
    # First by timestamp, then by ID (lexicographically)
    def <=>(other)
      return nil unless other.is_a?(Bound)

      result = timestamp <=> other.timestamp
      return result unless result.zero?

      id <=> other.id
    end

    def infinity?
      timestamp == INFINITY_TIMESTAMP
    end

    def min?
      timestamp.zero? && id.empty?
    end

    # Encode bound for transmission
    # @param prev_timestamp [Integer] previous timestamp for delta encoding
    # @return [String] encoded binary representation
    def encode(prev_timestamp = 0)
      result = "".b

      # Encode timestamp as delta from previous
      if infinity?
        result << Varint.encode(0) # 0 means infinity
      else
        result << Varint.encode(timestamp - prev_timestamp + 1)
      end

      # Encode ID length and prefix
      result << Varint.encode(id.bytesize)
      result << id unless id.empty?

      result
    end

    # Decode bound from binary data
    # @param io [StringIO] IO object to read from
    # @param prev_timestamp [Integer] previous timestamp for delta decoding
    # @return [Bound] decoded bound
    def self.decode(io, prev_timestamp = 0)
      encoded_timestamp = Varint.decode_from_io(io)

      timestamp = if encoded_timestamp.zero?
        INFINITY_TIMESTAMP
      else
        prev_timestamp + encoded_timestamp - 1
      end

      id_length = Varint.decode_from_io(io)
      id = id_length.positive? ? io.read(id_length) : "".b

      new(timestamp, id)
    end

    # Get the hex representation of the ID
    def id_hex
      id.unpack1("H*")
    end

    def to_s
      if infinity?
        "Bound(infinity)"
      elsif min?
        "Bound(min)"
      else
        "Bound(#{timestamp}, #{id_hex[0..15]}...)"
      end
    end

    def inspect
      to_s
    end

    def ==(other)
      other.is_a?(Bound) && timestamp == other.timestamp && id == other.id
    end

    def hash
      [ timestamp, id ].hash
    end

    alias eql? ==
  end
end
