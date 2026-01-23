# frozen_string_literal: true

module Negentropy
  # Performs Negentropy set reconciliation
  # Uses fingerprints to efficiently determine which IDs each side has
  class Reconciler
    # Default frame size limit (60KB)
    DEFAULT_FRAME_SIZE = 60_000

    # Threshold for switching from fingerprint to ID list
    ID_LIST_THRESHOLD = 20

    # Safety margin for frame size calculations
    FRAME_SIZE_MARGIN = 1_000

    attr_reader :storage, :frame_size_limit

    # @param storage [Storage] sealed storage containing local items
    # @param frame_size_limit [Integer] maximum message size in bytes
    def initialize(storage:, frame_size_limit: DEFAULT_FRAME_SIZE)
      raise ArgumentError, "Storage must be sealed" unless storage.sealed?

      @storage = storage
      @frame_size_limit = frame_size_limit
      @pending_ranges = []
    end

    # Generate initial message for sync initiation
    # @return [String] hex-encoded initial message
    def initiate
      message = Message.new

      lower = Bound.min
      upper = Bound.max

      if storage.empty?
        message.add_skip(upper)
      else
        fingerprint = storage.fingerprint(lower, upper)
        message.add_fingerprint(upper, fingerprint)
      end

      @pending_ranges = [[lower, upper]]
      message.to_hex
    end

    # Process incoming message and generate response
    # @param incoming_hex [String] hex-encoded incoming message
    # @return [Array<String, Array<String>, Array<String>>] [response_hex, have_ids, need_ids]
    #   response_hex is nil when reconciliation is complete
    #   have_ids are IDs we have that remote needs
    #   need_ids are IDs we need that remote has
    def reconcile(incoming_hex)
      incoming = Message.from_hex(incoming_hex)

      have_ids = []
      need_ids = []
      response = Message.new
      new_pending = []
      current_size = 1 # Protocol version byte
      estimate_prev_timestamp = 0

      lower = Bound.min

      # Handle empty message as implicit "skip to end" (remote has nothing)
      ranges = incoming.ranges
      if ranges.empty?
        ranges = [Message::Range.new(upper_bound: Bound.max, mode: Message::Mode::SKIP, payload: nil)]
      end

      ranges.each do |range|
        upper = range.upper_bound

        # Check if we're approaching frame size limit
        if current_size > frame_size_limit - FRAME_SIZE_MARGIN
          # Defer remaining ranges to next round
          new_pending << [lower, Bound.max]
          break
        end

        case range.mode
        when Message::Mode::SKIP
          # Remote has no data in this range, we skip too
          # nothing to do

        when Message::Mode::FINGERPRINT
          # Compare fingerprints
          local_fingerprint = storage.fingerprint(lower, upper)

          if Fingerprint.match?(local_fingerprint, range.fingerprint)
            # Fingerprints match - ranges are identical, add skip for alignment
            response.add_skip(upper)
            current_size += estimate_skip_size(upper, estimate_prev_timestamp)
            estimate_prev_timestamp = upper.timestamp unless upper.infinity?
          else
            # Fingerprints differ - need to subdivide
            added_size, estimate_prev_timestamp = handle_mismatch(
              lower,
              upper,
              response,
              new_pending,
              estimate_prev_timestamp
            )
            current_size += added_size
          end

        when Message::Mode::ID_LIST
          # Remote sent full ID list - compare with ours
          remote_ids = Set.new(range.ids)
          local_ids = Set.new(storage.range(lower, upper).map(&:id))

          # IDs we have that remote doesn't
          have_ids.concat((local_ids - remote_ids).map { |id| id.unpack1("H*") })

          # IDs remote has that we don't
          need_ids.concat((remote_ids - local_ids).map { |id| id.unpack1("H*") })

          # Add skip for alignment (ID_LIST is a terminal comparison)
          response.add_skip(upper)
          current_size += estimate_skip_size(upper, estimate_prev_timestamp)
          estimate_prev_timestamp = upper.timestamp unless upper.infinity?
        end

        lower = upper
      end

      @pending_ranges = new_pending

      # Check if reconciliation is complete
      # Complete only if: no pending ranges AND (response empty OR all skips)
      complete = new_pending.empty? && (response.empty? || response.ranges.all?(&:skip?))

      if complete
        [nil, have_ids, need_ids]
      else
        # If we have pending ranges but empty/all-skip response, compact the skips
        # and append fingerprints to preserve alignment and continue reconciliation.
        if new_pending.any? && (response.empty? || response.ranges.all?(&:skip?))
          response = Message.new
          current_size = 1 # protocol version byte
          estimate_prev_timestamp = 0

          first_lower = new_pending.first[0]
          unless first_lower.min?
            response.add_skip(first_lower)
            current_size += estimate_skip_size(first_lower, estimate_prev_timestamp)
            estimate_prev_timestamp = first_lower.timestamp unless first_lower.infinity?
          end

          remaining = new_pending.dup
          while remaining.any?
            lower_bound, upper_bound = remaining.shift
            range_size = estimate_fingerprint_size(upper_bound, estimate_prev_timestamp)

            if current_size + range_size > frame_size_limit - FRAME_SIZE_MARGIN
              remaining_lower = lower_bound
              remaining_upper = remaining.last ? remaining.last[1] : upper_bound
              collapsed_size = estimate_fingerprint_size(remaining_upper, estimate_prev_timestamp)
              response.add_fingerprint(remaining_upper, storage.fingerprint(remaining_lower, remaining_upper))
              current_size += collapsed_size
              estimate_prev_timestamp = remaining_upper.timestamp unless remaining_upper.infinity?
              break
            end

            response.add_fingerprint(upper_bound, storage.fingerprint(lower_bound, upper_bound))
            current_size += range_size
            estimate_prev_timestamp = upper_bound.timestamp unless upper_bound.infinity?
          end

          if current_size > frame_size_limit
            Rails.logger.warn(
              "[Negentropy::Reconciler] Response exceeds frame size limit " \
              "(#{current_size} > #{frame_size_limit})"
            )
          end
        end
        [response.to_hex, have_ids, need_ids]
      end
    end

    private

    def handle_mismatch(lower, upper, response, new_pending, prev_timestamp)
      count = storage.count_in_range(lower, upper)
      current_size = 0
      estimate_prev_timestamp = prev_timestamp

      if count <= ID_LIST_THRESHOLD
        # Small range - send full ID list
        ids = storage.range(lower, upper).map(&:id)
        response.add_id_list(upper, ids)
        current_size += estimate_id_list_size(upper, ids.size, estimate_prev_timestamp)
        estimate_prev_timestamp = upper.timestamp unless upper.infinity?
      else
        # Large range - subdivide and send fingerprints
        midpoint = storage.midpoint(lower, upper)

        # Lower half
        lower_fp = storage.fingerprint(lower, midpoint)
        response.add_fingerprint(midpoint, lower_fp)
        new_pending << [lower, midpoint]
        current_size += estimate_fingerprint_size(midpoint, estimate_prev_timestamp)
        estimate_prev_timestamp = midpoint.timestamp unless midpoint.infinity?

        # Upper half
        upper_fp = storage.fingerprint(midpoint, upper)
        response.add_fingerprint(upper, upper_fp)
        new_pending << [midpoint, upper]
        current_size += estimate_fingerprint_size(upper, estimate_prev_timestamp)
        estimate_prev_timestamp = upper.timestamp unless upper.infinity?
      end

      [current_size, estimate_prev_timestamp]
    end

    # Estimate size of a skip range in bytes
    def estimate_skip_size(bound, prev_timestamp)
      # Bound encoding + mode varint (1 byte for SKIP)
      estimate_bound_size(bound, prev_timestamp) + 1
    end

    # Estimate size of a fingerprint range in bytes
    def estimate_fingerprint_size(bound, prev_timestamp)
      # Bound encoding + mode varint (1 byte) + 16 byte fingerprint
      estimate_bound_size(bound, prev_timestamp) + 1 + Fingerprint::SIZE
    end

    # Estimate size of an ID list range in bytes
    def estimate_id_list_size(bound, id_count, prev_timestamp)
      # Bound encoding + mode varint (1 byte) + count varint + IDs (32 bytes each)
      estimate_bound_size(bound, prev_timestamp) + 1 + Varint.encode(id_count).bytesize + (id_count * Bound::ID_SIZE)
    end

    # Estimate size of a bound encoding
    def estimate_bound_size(bound, prev_timestamp)
      id_length = bound.id.bytesize
      timestamp_size = if bound.infinity?
        estimate_varint_size(0)
      else
        delta = bound.timestamp - prev_timestamp + 1
        estimate_varint_size(delta)
      end

      timestamp_size + estimate_varint_size(id_length) + id_length
    end

    # Estimate varint encoding size for a value
    def estimate_varint_size(value)
      return 1 if value < 128
      return 2 if value < 16_384
      return 3 if value < 2_097_152
      return 4 if value < 268_435_456

      5
    end
  end

end
