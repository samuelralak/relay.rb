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
      FilterMatcher.matches?(filters, event_data, check_search: false)
    end
  end
end
