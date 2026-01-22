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

    class_methods do
      def find_replaceable(pubkey:, kind:)
        where(pubkey: pubkey, kind: kind).active.newest_first.first
      end

      def find_addressable(pubkey:, kind:, d_tag:)
        where(pubkey: pubkey, kind: kind, d_tag: d_tag).active.newest_first.first
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
                             .where(tag_name: tag_name, tag_value: tag_values, deleted_at: nil)

          scope = scope.where(subquery.arel.exists)
        end

        scope
      end
    end
  end
end
