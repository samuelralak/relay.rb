# frozen_string_literal: true

module NostrRelay
  module Handlers
    # Handles incoming REQ messages (subscriptions).
    module Req
      module_function

      def call(connection:, sub_id:, filters:)
        unless valid_sub_id?(sub_id)
          connection.send_closed(sub_id, "#{Messages::Prefix::ERROR} invalid subscription id")
          return
        end

        result = Contracts::FiltersContract.new.call(filters:)
        unless result.success?
          connection.send_closed(sub_id, "#{Messages::Prefix::ERROR} #{result.errors[:filters].first}")
          return
        end

        success, error = Subscriptions.subscribe(
          connection_id: connection.id,
          sub_id:,
          filters:
        )

        unless success
          connection.send_closed(sub_id, error)
          return
        end

        send_historical_events(connection, sub_id, filters)

        connection.send_eose(sub_id)
      rescue StandardError => e
        Config.logger.error("[NostrRelay] REQ handler error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        connection.send_closed(sub_id, "#{Messages::Prefix::ERROR} internal error")
      end

      def valid_sub_id?(sub_id)
        sub_id.is_a?(String) && sub_id.length.between?(1, Config.max_subid_length)
      end

      def send_historical_events(connection, sub_id, filters)
        # Query events via configured repository adapter
        # Repository is responsible for column selection and query optimization
        # Use smallest limit from filters, capped at max_limit
        limit = extract_limit(filters)

        events = Config.event_repository
                   .matching_filters(filters)
                   .limit(limit)

        events.each do |event|
          connection.send_event(sub_id, Config.event_serializer.serialize(event))
        end
      end

      def extract_limit(filters)
        # Find the smallest limit specified in any filter, or use default
        filter_limits = filters.filter_map { |f| f[:limit] || f["limit"] }
        requested_limit = filter_limits.min || Config.default_limit

        # Cap at max_limit
        [ requested_limit, Config.max_limit ].min
      end
    end
  end
end
