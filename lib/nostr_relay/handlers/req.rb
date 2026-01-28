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
        limit = extract_limit(filters)

        if has_search_filter?(filters)
          send_search_results(connection, sub_id, filters, limit)
        else
          send_database_results(connection, sub_id, filters, limit)
        end
      end

      def has_search_filter?(filters)
        filters.any? { |f| f[:search].present? || f["search"].present? }
      end

      def send_search_results(connection, sub_id, filters, limit)
        # Search filters handled separately from non-search filters
        search_filters, regular_filters = filters.partition { |f| f[:search].present? || f["search"].present? }

        # Process search filters (relevance-ordered results)
        search_filters.each do |filter|
          search_query = filter[:search] || filter["search"]
          result = Search::ExecuteSearch.call(
            search_query:,
            filter: filter.except(:search, "search", :limit, "limit").symbolize_keys,
            limit:
          )

          if result.success?
            result.value![:events].each do |event|
              connection.send_event(sub_id, Config.event_serializer.serialize(event))
            end
          elsif result.failure == :search_disabled
            # Fallback: treat as regular filter without search
            regular_filters << filter.except(:search, "search")
          end
          # :search_error or :empty_query silently returns no results
        end

        # Process regular filters if any
        send_database_results(connection, sub_id, regular_filters, limit) if regular_filters.any?
      end

      def send_database_results(connection, sub_id, filters, limit)
        return if filters.empty?

        # Use OpenSearch for fast queries on large datasets
        # Falls back to PostgreSQL internally if unavailable or for tag filters
        result = Search::QueryByFilters.call(filters:, limit:)

        result.value![:events].each do |event|
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
