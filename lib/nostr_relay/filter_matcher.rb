# frozen_string_literal: true

module NostrRelay
  # Unified filter matching logic for NIP-01 subscription filters.
  # Used by both Subscription (for matches_data?) and Subscriptions (for broadcast matching).
  module FilterMatcher
    module_function

    # Match event against multiple filters (OR logic per NIP-01)
    # @param filters [Array<Hash>] subscription filters
    # @param event_hash [Hash] event data with string or symbol keys
    # @param check_search [Boolean] whether to check NIP-50 search filter (default: true)
    # @return [Boolean] true if any filter matches
    def matches?(filters, event_hash, check_search: true)
      data = event_hash.transform_keys(&:to_s)

      # NIP-42: Auth events (kind 22242) never match subscriptions
      return false if data["kind"] == Events::Kinds::AUTH

      filters.any? { |filter| filter_matches?(filter, data, check_search:) }
    end

    # Match event against a single filter
    # @param filter [Hash] NIP-01 filter
    # @param data [Hash] event data with string keys
    # @param check_search [Boolean] whether to check NIP-50 search filter
    # @return [Boolean] true if filter matches
    def filter_matches?(filter, data, check_search: true)
      filter = filter.transform_keys(&:to_s)

      return false if filter["kinds"] && !filter["kinds"].include?(data["kind"])
      return false if filter["authors"] && !filter["authors"].include?(data["pubkey"])
      return false if filter["ids"] && !filter["ids"].include?(data["id"])
      return false if filter["since"] && data["created_at"] < filter["since"]
      return false if filter["until"] && data["created_at"] > filter["until"]
      return false unless tags_match?(filter, data["tags"])
      return false if check_search && filter["search"].present? && !content_matches_search?(data["content"], filter["search"])

      true
    end

    # Check if all tag filters match event tags
    # @param filter [Hash] filter with potential #a, #e, #p, etc. keys
    # @param tags [Array] event tags array
    # @return [Boolean] true if all tag filters match
    def tags_match?(filter, tags)
      filter.all? do |key, values|
        next true unless key.match?(/\A#[a-zA-Z]\z/)
        tag_values_match?(key[1], Array(values), tags)
      end
    end

    # Check if any filter tag value matches any event tag value
    # @param tag_name [String] single letter tag name (e.g., "e", "p")
    # @param filter_values [Array] values to match
    # @param tags [Array] event tags array
    # @return [Boolean] true if any value matches
    def tag_values_match?(tag_name, filter_values, tags)
      return true if filter_values.empty?
      return false unless tags.is_a?(Array)

      event_vals = tags
        .select { |t| t.is_a?(Array) && t[0] == tag_name && t.size >= 2 }
        .map { |t| t[1] }

      (event_vals & filter_values).any?
    end

    # NIP-50: Simple term matching for search filter
    # @param content [String] event content
    # @param query [String] search query
    # @return [Boolean] true if all terms found in content
    def content_matches_search?(content, query)
      return true if query.blank?
      terms = query.downcase.split.reject { |t| t.start_with?("-") || t.include?(":") }
      terms.all? { |term| content.to_s.downcase.include?(term) }
    end
  end
end
