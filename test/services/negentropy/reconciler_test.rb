# frozen_string_literal: true

require "test_helper"

module Negentropy
  class ReconcilerTest < ActiveSupport::TestCase
    test "requires sealed storage" do
      storage = Storage.new
      assert_raises(ArgumentError) { Reconciler.new(storage: storage) }
    end

    test "initiate with empty storage" do
      storage = Storage.new
      storage.seal

      reconciler = Reconciler.new(storage: storage)
      message_hex = reconciler.initiate

      message = Message.from_hex(message_hex)
      # Trailing skips are optimized away per protocol spec
      # Empty storage produces a skip which is optimized to empty message
      assert_equal 0, message.size
    end

    test "initiate with items sends fingerprint" do
      storage = create_storage_with_events([100, 200, 300])

      reconciler = Reconciler.new(storage: storage)
      message_hex = reconciler.initiate

      message = Message.from_hex(message_hex)
      assert_equal 1, message.size
      assert message.ranges.first.fingerprint?
    end

    test "reconcile matching fingerprints returns complete" do
      # Both sides have same events
      storage1 = create_storage_with_events([100, 200])
      storage2 = create_storage_with_events([100, 200])

      client = Negentropy::ClientReconciler.new(storage: storage1)
      server = Negentropy::ServerReconciler.new(storage: storage2)

      # Client initiates
      initial_msg = client.initiate

      # Server processes
      response_hex, server_have, server_need = server.process_request(initial_msg)

      # Since fingerprints match, server should send skip
      response = Message.from_hex(response_hex)
      assert response.ranges.all?(&:skip?)
      assert_empty server_have
      assert_empty server_need
    end

    test "reconcile finds missing events on client" do
      # Server has more events
      storage1 = create_storage_with_events([100])
      storage2 = create_storage_with_events([100, 200])

      client = Negentropy::ClientReconciler.new(storage: storage1)
      server = Negentropy::ServerReconciler.new(storage: storage2)

      # Run reconciliation
      initial_msg = client.initiate
      response_hex, _server_have, server_need = server.process_request(initial_msg)

      # Server doesn't need anything from client
      assert_empty server_need

      # Client processes server response to find what it needs
      assert response_hex, "Server should respond with ID list"
      _result_hex, client_have, client_need = client.process_response(response_hex)

      # Client should identify that it needs event 200 from server
      assert_not_empty client_need, "Client should identify missing events"
      # Client has no extra events the server needs
      assert_empty client_have
    end

    test "reconcile finds missing events on server" do
      # Client has more events
      storage1 = create_storage_with_events([100, 200])
      storage2 = create_storage_with_events([100])

      client = Negentropy::ClientReconciler.new(storage: storage1)
      server = Negentropy::ServerReconciler.new(storage: storage2)

      # Run reconciliation
      initial_msg = client.initiate
      response_hex, _server_have, _server_need = server.process_request(initial_msg)

      # Client processes server response
      assert response_hex, "Server should respond with ID list"
      _result_hex, client_have, client_need = client.process_response(response_hex)

      # Client should identify that it has event 200 that server needs
      assert_not_empty client_have, "Client should identify events server needs"
      # Client doesn't need anything from server
      assert_empty client_need
    end

    test "complete reconciliation loop" do
      # Create storages with some overlap
      storage1 = create_storage_with_ids(["a" * 64, "b" * 64])
      storage2 = create_storage_with_ids(["b" * 64, "c" * 64])

      client = Negentropy::ClientReconciler.new(storage: storage1)
      server = Negentropy::ServerReconciler.new(storage: storage2)

      all_client_have = []
      all_client_need = []
      all_server_have = []
      all_server_need = []

      # Initial message
      msg = client.initiate

      # Reconciliation loop
      10.times do
        response_hex, server_have, server_need = server.process_request(msg)
        all_server_have.concat(server_have)
        all_server_need.concat(server_need)

        break unless response_hex

        msg, client_have, client_need = client.process_response(response_hex)
        all_client_have.concat(client_have)
        all_client_need.concat(client_need)

        break unless msg
      end

      # After reconciliation:
      # - Client has "a" that server needs
      # - Server has "c" that client needs
      combined_have = (all_client_have + all_server_have).uniq
      combined_need = (all_client_need + all_server_need).uniq

      # The "a" ID should be in client's have list (server needs it)
      # The "c" ID should be in server's have list (client needs it)
      assert combined_have.include?("a" * 64) || combined_need.include?("a" * 64)
      assert combined_have.include?("c" * 64) || combined_need.include?("c" * 64)
    end

    test "handles empty vs populated storage" do
      storage1 = Storage.new
      storage1.seal
      storage2 = create_storage_with_events([100, 200])

      client = Negentropy::ClientReconciler.new(storage: storage1)
      server = Negentropy::ServerReconciler.new(storage: storage2)

      initial_msg = client.initiate
      response_hex, server_have, server_need = server.process_request(initial_msg)

      # Server has all events, client has none
      assert_equal 2, server_have.size
      assert_empty server_need
    end

    test "handles populated vs empty storage" do
      storage1 = create_storage_with_events([100, 200])
      storage2 = Storage.new
      storage2.seal

      client = Negentropy::ClientReconciler.new(storage: storage1)
      server = Negentropy::ServerReconciler.new(storage: storage2)

      initial_msg = client.initiate
      response_hex, server_have, server_need = server.process_request(initial_msg)

      if response_hex
        msg, client_have, client_need = client.process_response(response_hex)
        # Client has events that empty server needs
        assert_not_empty client_have
      end
    end

    test "subdivides large ranges" do
      # Create storage with more events than ID_LIST_THRESHOLD
      timestamps = (1..30).map { |i| i * 100 }
      storage = create_storage_with_events(timestamps)

      reconciler = Reconciler.new(storage: storage)
      message_hex = reconciler.initiate

      # The initial message should have fingerprint(s)
      message = Message.from_hex(message_hex)
      assert message.ranges.any?(&:fingerprint?)
    end

    test "defers ranges preserves alignment when frame limit reached" do
      storage = Storage.new
      storage.add({ id: "a" * 64, created_at: 100 })
      storage.add({ id: "b" * 64, created_at: 200 })
      storage.add({ id: "c" * 64, created_at: 400_000_000 })
      storage.seal

      upper = Bound.new(300_000_000, "\x00".b * Bound::ID_SIZE)
      message = Message.new
      message.add_fingerprint(upper, storage.fingerprint(Bound.min, upper))
      message.add_fingerprint(Bound.max, storage.fingerprint(upper, Bound.max))

      reconciler = Reconciler.new(storage: storage, frame_size_limit: 1039)
      response_hex, have_ids, need_ids = reconciler.reconcile(message.to_hex)

      assert response_hex, "Expected a response when frame limit defers ranges"
      assert_empty have_ids
      assert_empty need_ids

      response = Message.from_hex(response_hex)
      assert_equal 2, response.size
      assert response.ranges.first.skip?
      assert_equal upper, response.ranges.first.upper_bound
      assert response.ranges.last.fingerprint?
      assert_equal Bound.max, response.ranges.last.upper_bound
    end

    private

    def create_storage_with_events(timestamps)
      storage = Storage.new
      timestamps.each_with_index do |ts, i|
        storage.add({ id: "#{('a'.ord + i).chr}" * 64, created_at: ts })
      end
      storage.seal
      storage
    end

    def create_storage_with_ids(hex_ids)
      storage = Storage.new
      hex_ids.each_with_index do |id, i|
        storage.add({ id: id, created_at: (i + 1) * 100 })
      end
      storage.seal
      storage
    end
  end
end
