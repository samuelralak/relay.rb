# frozen_string_literal: true

module Negentropy
  # Storage adapter for Negentropy reconciliation
  # Provides interface to query events and compute fingerprints for ranges
  class Storage
    # Item represents an event in sorted order (timestamp, id)
    Item = Struct.new(:timestamp, :id, keyword_init: true) do
      include Comparable

      def <=>(other)
        result = timestamp <=> other.timestamp
        return result unless result.zero?

        id <=> other.id
      end

      def bound
        Bound.new(timestamp, id)
      end

      # Convert hex ID to binary
      def self.from_event(event)
        timestamp = event.is_a?(Hash) ? event[:created_at] : event.nostr_created_at.to_i
        hex_id = event.is_a?(Hash) ? event[:id] : event.event_id
        binary_id = [hex_id].pack("H*")
        new(timestamp: timestamp, id: binary_id)
      end
    end

    attr_reader :items

    def initialize
      @items = []
      @sealed = false
    end

    # Add an event to the storage
    # @param event [Event, Hash] event to add
    def add(event)
      raise "Storage is sealed" if @sealed

      @items << Item.from_event(event)
    end

    # Add multiple events
    # @param events [Array<Event, Hash>] events to add
    def add_all(events)
      events.each { |e| add(e) }
    end

    # Seal the storage (sort and prepare for queries)
    # Must be called before any queries
    def seal
      @items.sort!
      @sealed = true
    end

    def sealed?
      @sealed
    end

    def size
      @items.size
    end

    def empty?
      @items.empty?
    end

    # Find index of first item >= bound
    # @param bound [Bound] lower bound
    # @return [Integer] index
    def find_lower_bound(bound)
      return 0 if @items.empty?

      @items.bsearch_index { |item| item.bound >= bound } || @items.size
    end

    # Get items in range [lower_bound, upper_bound)
    # @param lower [Bound] lower bound (inclusive)
    # @param upper [Bound] upper bound (exclusive)
    # @return [Array<Item>] items in range
    def range(lower, upper)
      raise "Storage must be sealed" unless @sealed

      start_idx = find_lower_bound(lower)
      return [] if start_idx >= @items.size

      end_idx = find_lower_bound(upper)
      @items[start_idx...end_idx]
    end

    # Count items in range
    # @param lower [Bound] lower bound
    # @param upper [Bound] upper bound
    # @return [Integer] count
    def count_in_range(lower, upper)
      range(lower, upper).size
    end

    # Compute fingerprint for items in range
    # @param lower [Bound] lower bound
    # @param upper [Bound] upper bound
    # @return [String] 16-byte fingerprint
    def fingerprint(lower, upper)
      items_in_range = range(lower, upper)
      ids = items_in_range.map(&:id)
      Fingerprint.compute(ids)
    end

    # Get all IDs in range (as hex strings)
    # @param lower [Bound] lower bound
    # @param upper [Bound] upper bound
    # @return [Array<String>] hex event IDs
    def ids_in_range(lower, upper)
      range(lower, upper).map { |item| item.id.unpack1("H*") }
    end

    # Split a range at the midpoint
    # @param lower [Bound] lower bound
    # @param upper [Bound] upper bound
    # @return [Bound] midpoint bound
    def midpoint(lower, upper)
      items_in_range = range(lower, upper)
      return lower if items_in_range.empty?

      mid_idx = items_in_range.size / 2
      items_in_range[mid_idx].bound
    end

    # Create from ActiveRecord scope
    # @param scope [ActiveRecord::Relation] events scope
    # @return [Storage] new storage with events loaded
    def self.from_scope(scope)
      storage = new
      scope.find_each do |event|
        storage.add(event)
      end
      storage.seal
      storage
    end

    # Create from array of events
    # @param events [Array<Event, Hash>] events
    # @return [Storage] new storage with events loaded
    def self.from_array(events)
      storage = new
      storage.add_all(events)
      storage.seal
      storage
    end
  end
end
