# frozen_string_literal: true

module Events
  module Filterable
    extend ActiveSupport::Concern

    included do
      scope :by_event_ids, ->(ids) { ids.present? ? where(event_id: ids) : all }
      scope :by_authors, ->(pubkeys) { pubkeys.present? ? where(pubkey: pubkeys) : all }
      scope :by_kinds, ->(kinds) { kinds.present? ? where(kind: kinds) : all }
      scope :since, ->(timestamp) { timestamp.present? ? where("nostr_created_at >= ?", Time.at(timestamp).utc) : all }
      scope :until_time, ->(timestamp) { timestamp.present? ? where("nostr_created_at <= ?", Time.at(timestamp).utc) : all }
      scope :active, -> { not_expired }
      scope :newest_first, -> { order(nostr_created_at: :desc) }
      scope :oldest_first, -> { order(nostr_created_at: :asc) }
    end

    # Instance method for subscription matching (live events)
    # Checks if this event matches a given filter
    def matches_filter?(filter)
      filter = filter.with_indifferent_access

      # Check ids
      return false if filter[:ids].present? && !filter[:ids].include?(event_id)

      # Check authors
      return false if filter[:authors].present? && !filter[:authors].include?(pubkey)

      # Check kinds
      return false if filter[:kinds].present? && !filter[:kinds].include?(kind)

      # Check since (event must be >= since)
      return false if filter[:since].present? && nostr_created_at < Time.at(filter[:since]).utc

      # Check until (event must be <= until)
      return false if filter[:until].present? && nostr_created_at > Time.at(filter[:until]).utc

      # Check tag filters
      filter.each do |key, values|
        next unless key.to_s.match?(/\A#[a-zA-Z]\z/)

        tag_name = key.to_s[1]
        tag_values = Array(values)
        return false unless tag_matches?(tag_name, tag_values)
      end

      true
    end

    private

    # Check if any of the event's tags match the filter
    # Uses cached tag lookup for efficiency when checking multiple tag filters
    def tag_matches?(tag_name, filter_values)
      tag_values_for_name = tag_lookup[tag_name] || []
      (tag_values_for_name & filter_values).any?
    end

    # Build a cached lookup of tag_name => [tag_values]
    # Called once per event, reused for all tag filter checks
    def tag_lookup
      @tag_lookup ||= tags.each_with_object(Hash.new { |h, k| h[k] = [] }) do |tag, lookup|
        next unless tag.is_a?(Array) && tag[0].is_a?(String) && tag.size >= 2

        lookup[tag[0]] << tag[1]
      end
    end

    class_methods do
      def find_replaceable(pubkey:, kind:)
        where(pubkey:, kind:).active.newest_first.first
      end

      def find_addressable(pubkey:, kind:, d_tag:)
        where(pubkey:, kind:, d_tag:).active.newest_first.first
      end

      def matching_filter(filter)
        filter = filter.with_indifferent_access
        scope = active.newest_first

        scope = scope.by_event_ids(filter[:ids])
        scope = scope.by_authors(filter[:authors])
        scope = scope.by_kinds(filter[:kinds])
        scope = scope.since(filter[:since])
        scope = scope.until_time(filter[:until])

        # Collect tag filters and apply them efficiently
        tag_filters = extract_tag_filters(filter)
        scope = apply_tag_filters(scope, tag_filters) if tag_filters.any?

        scope = scope.limit(filter[:limit]) if filter[:limit].present?
        scope
      end

      # Match events against multiple filters with OR logic
      # NIP-01: Event matches subscription if it matches ANY of the filters
      def matching_filters(filters)
        return none if filters.blank?

        # Build UNION of all filter queries
        # Each filter is applied independently, results are combined
        queries = filters.map { |f| matching_filter(f) }

        # Use Arel to build UNION query for efficiency
        if queries.size == 1
          queries.first
        else
          # Combine all queries with UNION and wrap in subquery
          combined = queries.map(&:arel).reduce { |acc, q| acc.union(q) }
          from(Arel::Nodes::TableAlias.new(combined, :events)).newest_first
        end
      end

      private

      def tag_filter_key?(key)
        key.to_s.match?(/\A#[a-zA-Z]\z/)
      end

      def extract_tag_filters(filter)
        filter.each_with_object({}) do |(key, values), tags|
          next unless tag_filter_key?(key)

          tags[key.to_s[1]] = Array(values)
        end
      end

      # Apply tag filters using subqueries instead of multiple JOINs
      # This is more efficient for multiple tag filters
      def apply_tag_filters(scope, tag_filters)
        tag_filters.each do |tag_name, tag_values|
          # Use EXISTS subquery for each tag filter - more efficient than JOIN
          subquery = EventTag.where(EventTag.arel_table[:event_id].eq(Event.arel_table[:id]))
                             .where(tag_name:, tag_value: tag_values, deleted_at: nil)

          scope = scope.where(subquery.arel.exists)
        end

        scope
      end
    end
  end
end
