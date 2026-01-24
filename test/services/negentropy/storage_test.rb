# frozen_string_literal: true

require "test_helper"

module Negentropy
  class StorageTest < ActiveSupport::TestCase
    setup do
      @storage = Storage.new
    end

    test "starts empty and unsealed" do
      assert @storage.empty?
      assert_not @storage.sealed?
    end

    test "can add events" do
      event = { id: "a" * 64, created_at: Time.current.to_i }
      @storage.add(event)

      assert_equal 1, @storage.size
    end

    test "seal sorts items" do
      event1 = { id: "a" * 64, created_at: 100 }
      event2 = { id: "b" * 64, created_at: 50 }
      event3 = { id: "c" * 64, created_at: 150 }

      @storage.add(event1)
      @storage.add(event2)
      @storage.add(event3)
      @storage.seal

      assert @storage.sealed?
      assert_equal 50, @storage.items.first.timestamp
      assert_equal 150, @storage.items.last.timestamp
    end

    test "cannot add after sealing" do
      @storage.seal
      assert_raises(RuntimeError) { @storage.add({ id: "a" * 64, created_at: 100 }) }
    end

    test "range queries" do
      add_events([ 100, 200, 300 ])

      lower = Bound.new(150, "")
      upper = Bound.new(250, "")

      items = @storage.range(lower, upper)
      assert_equal 1, items.size
      assert_equal 200, items.first.timestamp
    end

    test "fingerprint for range" do
      add_events([ 100, 200, 300 ])

      lower = Bound.min
      upper = Bound.max

      fp = @storage.fingerprint(lower, upper)
      assert_equal 16, fp.bytesize
      assert_not Fingerprint.empty?(fp)
    end

    test "midpoint" do
      add_events([ 100, 200, 300, 400 ])

      lower = Bound.min
      upper = Bound.max

      mid = @storage.midpoint(lower, upper)
      assert_equal 300, mid.timestamp
    end

    test "from_array class method" do
      events = [
        { id: "a" * 64, created_at: 100 },
        { id: "b" * 64, created_at: 200 }
      ]

      storage = Storage.from_array(events)
      assert storage.sealed?
      assert_equal 2, storage.size
    end

    private

    def add_events(timestamps)
      timestamps.each_with_index do |ts, i|
        @storage.add({ id: "#{i}" * 64, created_at: ts })
      end
      @storage.seal
    end
  end
end
