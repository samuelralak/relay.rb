# frozen_string_literal: true

module Negentropy
  # Encodes and decodes Negentropy protocol messages
  # Message format: <protocolVersion> <Range>*
  # Range format: <upperBound> <mode> <payload>
  class Message
    PROTOCOL_VERSION = 0x61 # v1

    # Mode values for ranges
    module Mode
      SKIP = 0        # Empty payload - no data for this range
      FINGERPRINT = 1 # 16-byte fingerprint
      ID_LIST = 2     # varint count + list of 32-byte IDs
    end

    # Represents a single range in a message
    Range = Struct.new(:upper_bound, :mode, :payload, keyword_init: true) do
      def fingerprint?
        mode == Mode::FINGERPRINT
      end

      def id_list?
        mode == Mode::ID_LIST
      end

      def skip?
        mode == Mode::SKIP
      end

      def fingerprint
        raise "Not a fingerprint range" unless fingerprint?

        payload
      end

      def ids
        raise "Not an ID list range" unless id_list?

        payload
      end
    end

    attr_reader :ranges

    def initialize
      @ranges = []
    end

    # Add a skip range
    def add_skip(upper_bound)
      @ranges << Range.new(upper_bound: upper_bound, mode: Mode::SKIP, payload: nil)
    end

    # Add a fingerprint range
    def add_fingerprint(upper_bound, fingerprint)
      @ranges << Range.new(upper_bound: upper_bound, mode: Mode::FINGERPRINT, payload: fingerprint)
    end

    # Add an ID list range
    # @param upper_bound [Bound] upper bound of range
    # @param ids [Array<String>] array of 32-byte binary IDs
    def add_id_list(upper_bound, ids)
      @ranges << Range.new(upper_bound: upper_bound, mode: Mode::ID_LIST, payload: ids)
    end

    # Encode message to binary
    # Trailing SKIPs are omitted per protocol spec
    # @return [String] binary message
    def encode
      result = "".b
      result << PROTOCOL_VERSION.chr

      prev_timestamp = 0

      # Find last non-skip range to optimize away trailing skips
      ranges_to_encode = @ranges.dup
      ranges_to_encode.pop while ranges_to_encode.last&.skip?

      ranges_to_encode.each do |range|
        # Encode upper bound with delta timestamp
        result << range.upper_bound.encode(prev_timestamp)
        prev_timestamp = range.upper_bound.timestamp unless range.upper_bound.infinity?

        # Encode mode
        result << Varint.encode(range.mode)

        # Encode payload
        case range.mode
        when Mode::FINGERPRINT
          result << range.payload
        when Mode::ID_LIST
          result << Varint.encode(range.payload.size)
          range.payload.each { |id| result << id }
        end
        # SKIP has no payload
      end

      result
    end

    # Encode to hex string (for transmission)
    # @return [String] hex-encoded message
    def to_hex
      encode.unpack1("H*")
    end

    # Decode message from binary
    # @param data [String] binary message
    # @return [Message] decoded message
    def self.decode(data)
      io = StringIO.new(data.b)

      version = io.getbyte
      raise ArgumentError, "Unsupported protocol version: #{version}" unless version == PROTOCOL_VERSION

      message = new
      prev_timestamp = 0

      until io.eof?
        # Decode upper bound
        upper_bound = Bound.decode(io, prev_timestamp)
        prev_timestamp = upper_bound.timestamp unless upper_bound.infinity?

        # Decode mode
        mode = Varint.decode_from_io(io)

        # Decode payload
        payload = case mode
        when Mode::SKIP
          nil
        when Mode::FINGERPRINT
          io.read(Fingerprint::SIZE)
        when Mode::ID_LIST
          count = Varint.decode_from_io(io)
          count.times.map { io.read(Bound::ID_SIZE) }
        else
          raise ArgumentError, "Unknown mode: #{mode}"
        end

        message.ranges << Range.new(upper_bound: upper_bound, mode: mode, payload: payload)
      end

      message
    end

    # Decode from hex string
    # @param hex [String] hex-encoded message
    # @return [Message] decoded message
    def self.from_hex(hex)
      decode([hex].pack("H*"))
    end

    def empty?
      @ranges.empty?
    end

    def size
      @ranges.size
    end
  end
end
