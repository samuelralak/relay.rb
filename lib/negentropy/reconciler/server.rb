# frozen_string_literal: true

module Negentropy
  class Reconciler
    # Server-side reconciler for responding to sync requests
    class Server < Reconciler
      # Process request from client and generate response
      # @param request_hex [String] hex-encoded request from client
      # @return [Array<String, Array<String>, Array<String>>] [response_hex, have_ids, need_ids]
      def process_request(request_hex)
        request = Message.from_hex(request_hex)

        have_ids = []
        need_ids = []
        response = Message.new

        lower = Bound.min

        # Handle empty message as implicit "skip to end" (client has nothing)
        ranges = request.ranges
        if ranges.empty?
          ranges = [ Message::Range.new(upper_bound: Bound.max, mode: Message::Mode::SKIP, payload: nil) ]
        end

        ranges.each do |range|
          upper = range.upper_bound

          case range.mode
          when Message::Mode::SKIP
            # Client has no data - send our IDs if any
            local_ids = storage.range(lower, upper).map(&:id)
            if local_ids.any?
              have_ids.concat(local_ids.map { |id| id.unpack1("H*") })
              response.add_id_list(upper, local_ids)
            else
              response.add_skip(upper)
            end

          when Message::Mode::FINGERPRINT
            # Compare fingerprints
            local_fingerprint = storage.fingerprint(lower, upper)

            if Fingerprint.match?(local_fingerprint, range.fingerprint)
              response.add_skip(upper)
            else
              handle_mismatch_server(lower, upper, response, have_ids)
            end

          when Message::Mode::ID_LIST
            # Compare ID lists
            remote_ids = Set.new(range.ids)
            local_items = storage.range(lower, upper)
            local_ids = Set.new(local_items.map(&:id))

            # IDs we have that remote doesn't
            have_ids.concat((local_ids - remote_ids).map { |id| id.unpack1("H*") })

            # IDs remote has that we don't
            need_ids.concat((remote_ids - local_ids).map { |id| id.unpack1("H*") })

            # Send our ID list back
            response.add_id_list(upper, local_items.map(&:id))
          end

          lower = upper
        end

        [ response.to_hex, have_ids, need_ids ]
      end

      private

      def handle_mismatch_server(lower, upper, response, have_ids)
        count = storage.count_in_range(lower, upper)
        local_items = storage.range(lower, upper)

        if count <= ID_LIST_THRESHOLD
          # Small range - send full ID list
          ids = local_items.map(&:id)
          response.add_id_list(upper, ids)
        else
          # Large range - subdivide and send fingerprints
          midpoint = storage.midpoint(lower, upper)

          # Lower half
          lower_fp = storage.fingerprint(lower, midpoint)
          response.add_fingerprint(midpoint, lower_fp)

          # Upper half
          upper_fp = storage.fingerprint(midpoint, upper)
          response.add_fingerprint(upper, upper_fp)
        end
      end
    end
  end
end
