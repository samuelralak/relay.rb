# frozen_string_literal: true

module Negentropy
  # Performs Negentropy set reconciliation
  # Uses fingerprints to efficiently determine which IDs each side has
  class Reconciler
    # Default frame size limit (60KB)
    DEFAULT_FRAME_SIZE = 60_000

    # Threshold for switching from fingerprint to ID list
    ID_LIST_THRESHOLD = 20

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

      lower = Bound.min

      incoming.ranges.each do |range|
        upper = range.upper_bound

        case range.mode
        when Message::Mode::SKIP
          # Remote has no data in this range, we skip too
          # nothing to do

        when Message::Mode::FINGERPRINT
          # Compare fingerprints
          local_fingerprint = storage.fingerprint(lower, upper)

          if Fingerprint.match?(local_fingerprint, range.fingerprint)
            # Fingerprints match - ranges are identical
            response.add_skip(upper) unless new_pending.empty?
          else
            # Fingerprints differ - need to subdivide
            handle_mismatch(lower, upper, response, new_pending)
          end

        when Message::Mode::ID_LIST
          # Remote sent full ID list - compare with ours
          remote_ids = Set.new(range.ids)
          local_ids = Set.new(storage.range(lower, upper).map(&:id))

          # IDs we have that remote doesn't
          have_ids.concat((local_ids - remote_ids).map { |id| id.unpack1("H*") })

          # IDs remote has that we don't
          need_ids.concat((remote_ids - local_ids).map { |id| id.unpack1("H*") })

          response.add_skip(upper) unless new_pending.empty?
        end

        lower = upper
      end

      @pending_ranges = new_pending

      # Check if reconciliation is complete
      if response.empty? || (response.ranges.all?(&:skip?) && new_pending.empty?)
        [nil, have_ids, need_ids]
      else
        [response.to_hex, have_ids, need_ids]
      end
    end

    private

    def handle_mismatch(lower, upper, response, new_pending)
      count = storage.count_in_range(lower, upper)

      if count <= ID_LIST_THRESHOLD
        # Small range - send full ID list
        ids = storage.range(lower, upper).map(&:id)
        response.add_id_list(upper, ids)
      else
        # Large range - subdivide and send fingerprints
        midpoint = storage.midpoint(lower, upper)

        # Lower half
        lower_fp = storage.fingerprint(lower, midpoint)
        response.add_fingerprint(midpoint, lower_fp)
        new_pending << [lower, midpoint]

        # Upper half
        upper_fp = storage.fingerprint(midpoint, upper)
        response.add_fingerprint(upper, upper_fp)
        new_pending << [midpoint, upper]
      end
    end
  end

end
