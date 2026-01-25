# frozen_string_literal: true

module NostrTestHelpers
  # Mock WebSocket for testing
  class MockWebSocket
    attr_reader :messages, :closed

    def initialize
      @messages = []
      @closed = false
    end

    def send(data)
      @messages << data
    end

    def close
      @closed = true
    end

    def last_message
      @messages.last
    end

    def last_message_parsed
      JSON.parse(last_message) if last_message
    end

    def clear!
      @messages.clear
    end
  end

  # Mock Connection wrapping MockWebSocket for NostrRelay testing
  class MockConnection
    attr_reader :id, :ws, :sent_messages

    def initialize
      @id = SecureRandom.uuid
      @ws = MockWebSocket.new
      @sent_messages = []
    end

    def send_event(sub_id, event)
      msg = [ "EVENT", sub_id, event ]
      @sent_messages << msg
      @ws.send(msg.to_json)
    end

    def send_ok(event_id, success, message = "")
      msg = [ "OK", event_id, success, message ]
      @sent_messages << msg
      @ws.send(msg.to_json)
    end

    def send_eose(sub_id)
      msg = [ "EOSE", sub_id ]
      @sent_messages << msg
      @ws.send(msg.to_json)
    end

    def send_closed(sub_id, message)
      msg = [ "CLOSED", sub_id, message ]
      @sent_messages << msg
      @ws.send(msg.to_json)
    end

    def send_notice(message)
      msg = [ "NOTICE", message ]
      @sent_messages << msg
      @ws.send(msg.to_json)
    end

    def last_sent
      @sent_messages.last
    end

    def clear!
      @sent_messages.clear
      @ws.clear!
    end
  end

  # Valid hex strings for testing
  HEX_64 = "a" * 64
  HEX_64_ALT = "b" * 64
  HEX_128 = "c" * 128

  # Invalid hex examples
  INVALID_HEX_UPPERCASE = "A" * 64
  INVALID_HEX_NON_HEX = "g" * 64
  INVALID_HEX_TOO_SHORT = "a" * 63
  INVALID_HEX_TOO_LONG = "a" * 65

  # Build a valid event hash with sensible defaults
  def build_event_attrs(overrides = {})
    event_id = overrides.delete(:event_id) || unique_hex(64)
    {
      event_id:,
      pubkey: HEX_64_ALT,
      nostr_created_at: Time.current,
      kind: 1,
      tags: [ [ "t", "test" ] ],
      content: "test content",
      sig: HEX_128,
      raw_event: { id: event_id }
    }.merge(overrides)
  end

  # Create and save a valid event
  def create_event(overrides = {})
    Event.create!(build_event_attrs(overrides))
  end

  # Generate unique hex string
  def unique_hex(length)
    SecureRandom.hex(length / 2)
  end

  # Custom assertions
  def assert_invalid(record, attribute, message = nil)
    assert_not record.valid?, "Expected record to be invalid"
    if message
      assert_includes record.errors[attribute], message,
                      "Expected #{attribute} errors to include '#{message}'"
    else
      assert record.errors[attribute].any?,
             "Expected errors on #{attribute}"
    end
  end

  def assert_valid(record)
    assert record.valid?, "Expected record to be valid, got errors: #{record.errors.full_messages.join(', ')}"
  end

  def assert_scope_filters(scope, &block)
    scope.each { |record| assert yield(record), "Scope included record that doesn't match filter" }
  end

  def assert_ordered_desc(records, attribute)
    values = records.map(&attribute)
    assert_equal values.sort.reverse, values, "Expected #{attribute} to be in descending order"
  end

  def assert_ordered_asc(records, attribute)
    values = records.map(&attribute)
    assert_equal values.sort, values, "Expected #{attribute} to be in ascending order"
  end
end
