# frozen_string_literal: true

module Negentropy
  # Variable-length integer encoding for Negentropy protocol
  # Uses base-128 with MSB continuation bit (high bit set on all bytes except last)
  module Varint
    module_function

    # Encode an integer to varint bytes
    # @param value [Integer] non-negative integer to encode
    # @return [String] binary string of encoded bytes
    def encode(value)
      raise ArgumentError, "Value must be non-negative" if value.negative?

      return "\x00".b if value.zero?

      bytes = []

      # Extract base-128 digits
      temp = value
      while temp.positive?
        bytes.unshift(temp & 0x7F)
        temp >>= 7
      end

      # Set continuation bit on all bytes except last
      (0...(bytes.length - 1)).each do |i|
        bytes[i] |= 0x80
      end

      bytes.pack("C*")
    end

    # Decode varint from a binary string
    # @param data [String] binary string to decode from
    # @param offset [Integer] starting position in the string
    # @return [Array<Integer, Integer>] [decoded_value, bytes_consumed]
    def decode(data, offset = 0)
      value = 0
      bytes_read = 0

      loop do
        raise ArgumentError, "Unexpected end of data" if offset + bytes_read >= data.bytesize

        byte = data.getbyte(offset + bytes_read)
        bytes_read += 1

        value = (value << 7) | (byte & 0x7F)

        break if (byte & 0x80).zero?

        raise ArgumentError, "Varint too long" if bytes_read > 10
      end

      [ value, bytes_read ]
    end

    # Decode varint from a StringIO-like object
    # @param io [StringIO] IO object to read from
    # @return [Integer] decoded value
    def decode_from_io(io)
      value = 0
      bytes_read = 0

      loop do
        byte = io.getbyte
        raise ArgumentError, "Unexpected end of data" if byte.nil?

        bytes_read += 1
        value = (value << 7) | (byte & 0x7F)

        break if (byte & 0x80).zero?

        raise ArgumentError, "Varint too long" if bytes_read > 10
      end

      value
    end
  end
end
