# frozen_string_literal: true

module EventTags
  module Queryable
    extend ActiveSupport::Concern

    included do
      # Base tag scopes
      scope :by_tag_name, ->(name) { where(tag_name: name) }
      scope :by_tag_value, ->(value) { where(tag_value: value) }
      scope :by_tag, ->(name, value) { by_tag_name(name).by_tag_value(value) }
      scope :by_kind, ->(kind) { kind.present? ? where(kind: kind) : all }
      scope :by_kinds, ->(kinds) { kinds.present? ? where(kind: kinds) : all }

      # Common single-letter tag scopes
      scope :e_tags, -> { by_tag_name(TagNames::EVENT) }
      scope :p_tags, -> { by_tag_name(TagNames::PUBKEY) }
      scope :a_tags, -> { by_tag_name(TagNames::ADDRESSABLE) }
      scope :d_tags, -> { by_tag_name(TagNames::IDENTIFIER) }
      scope :t_tags, -> { by_tag_name(TagNames::HASHTAG) }
      scope :k_tags, -> { by_tag_name(TagNames::KIND) }
      scope :r_tags, -> { by_tag_name(TagNames::REFERENCE) }

      # Time-based scopes
      scope :since, ->(timestamp) { timestamp.present? ? where("nostr_created_at >= ?", Time.at(timestamp).utc) : all }
      scope :until_time, ->(timestamp) { timestamp.present? ? where("nostr_created_at <= ?", Time.at(timestamp).utc) : all }
      scope :in_time_range, ->(since_ts, until_ts) { since(since_ts).until_time(until_ts) }

      # Ordering scopes
      scope :newest_first, -> { order(nostr_created_at: :desc) }
      scope :oldest_first, -> { order(nostr_created_at: :asc) }
      scope :by_index, -> { order(tag_index: :asc) }
    end

    class_methods do
      # Efficient tag query using covering index
      # Returns event_ids matching the given tag criteria
      def event_ids_for_tag(tag_name:, tag_values:, since: nil, until_time: nil, kinds: nil, limit: 500)
        # PostgreSQL requires ORDER BY columns in SELECT for DISTINCT
        # Pluck both columns and extract unique event_ids preserving order
        by_tag_name(tag_name)
          .where(tag_value: tag_values)
          .since(since)
          .until_time(until_time)
          .by_kinds(kinds)
          .newest_first
          .limit(limit)
          .pluck(:event_id, :nostr_created_at)
          .map(&:first)
          .uniq
      end

      # Find events that reference a specific event
      def referencing_event(event_id, kinds: nil, limit: 500)
        event_ids_for_tag(
          tag_name: TagNames::EVENT,
          tag_values: [ event_id ],
          kinds: kinds,
          limit: limit
        )
      end

      # Find events that reference a specific pubkey
      def referencing_pubkey(pubkey, kinds: nil, limit: 500)
        event_ids_for_tag(
          tag_name: TagNames::PUBKEY,
          tag_values: [ pubkey ],
          kinds: kinds,
          limit: limit
        )
      end

      # Find events with a specific hashtag
      def with_hashtag(hashtag, kinds: nil, limit: 500)
        normalized = hashtag.to_s.downcase.delete_prefix("#")
        event_ids_for_tag(
          tag_name: TagNames::HASHTAG,
          tag_values: [ normalized ],
          kinds: kinds,
          limit: limit
        )
      end

      # Find addressable event references
      def referencing_addressable(coordinate, kinds: nil, limit: 500)
        event_ids_for_tag(
          tag_name: TagNames::ADDRESSABLE,
          tag_values: [ coordinate ],
          kinds: kinds,
          limit: limit
        )
      end
    end
  end
end
