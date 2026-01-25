# frozen_string_literal: true

require "dry-struct"
require "dry-types"

module NostrRelay
  module Types
    include Dry.Types()
  end

  # Represents a single subscription with its filters.
  # Uses dry-struct for immutable data.
  class Subscription < Dry::Struct
    attribute :sub_id, Types::Strict::String
    attribute :filters, Types::Strict::Array.of(Types::Hash)

    def matches?(event)
      filters.any? { |filter| event.matches_filter?(filter) }
    end

    def matches_data?(event_data)
      filters.any? { |filter| filter_matches_data?(filter, event_data) }
    end

    private

    def filter_matches_data?(filter, data)
      data = data.transform_keys(&:to_s)
      filter = filter.transform_keys(&:to_s)

      return false if filter["kinds"] && !filter["kinds"].include?(data["kind"])
      return false if filter["authors"] && !filter["authors"].include?(data["pubkey"])
      return false if filter["ids"] && !filter["ids"].include?(data["id"])
      return false if filter["since"] && data["created_at"] < filter["since"]
      return false if filter["until"] && data["created_at"] > filter["until"]

      # Check tag filters (#e, #p, etc.)
      filter.each do |key, values|
        next unless key.match?(/\A#[a-zA-Z]\z/)

        tag_name = key[1] # Extract single letter after #
        return false unless tag_matches_data?(tag_name, Array(values), data["tags"])
      end

      true
    end

    # Check if event data tags match the filter values
    def tag_matches_data?(tag_name, filter_values, tags)
      return true if filter_values.empty?
      return false unless tags.is_a?(Array)

      # Find all values for this tag name in the event's tags
      event_tag_values = tags
        .select { |t| t.is_a?(Array) && t[0] == tag_name && t.size >= 2 }
        .map { |t| t[1] }

      # Check if any filter value matches any event tag value
      (event_tag_values & filter_values).any?
    end
  end
end
