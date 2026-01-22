# frozen_string_literal: true

require "test_helper"

module Events
  class EventSerializerTest < ActiveSupport::TestCase
    setup do
      @text_note = events(:text_note)
      @metadata = events(:metadata)
      @reaction = events(:reaction)
      @long_form = events(:long_form)
    end

    # =========================================
    # NIP-01 Format
    # =========================================

    test "serializes to NIP-01 format" do
      result = EventSerializer.serialize(@text_note)

      assert_equal @text_note.event_id, result[:id]
      assert_equal @text_note.pubkey, result[:pubkey]
      assert_equal @text_note.nostr_created_at.to_i, result[:created_at]
      assert_equal @text_note.kind, result[:kind]
      assert_equal @text_note.tags, result[:tags]
      assert_equal @text_note.content, result[:content]
      assert_equal @text_note.sig, result[:sig]
    end

    test "uses NIP-01 field names" do
      result = EventSerializer.serialize(@text_note)
      assert_equal %i[id pubkey created_at kind tags content sig].sort, result.keys.sort
    end

    test "created_at is unix timestamp integer" do
      result = EventSerializer.serialize(@text_note)

      assert_kind_of Integer, result[:created_at]
      assert result[:created_at] > 0
    end

    test "tags preserves array structure" do
      result = EventSerializer.serialize(@text_note)

      assert_kind_of Array, result[:tags]
      result[:tags].each { |tag| assert_kind_of Array, tag }
    end

    # =========================================
    # Edge Cases
    # =========================================

    test "handles empty tags and content" do
      @metadata.tags = []
      assert_equal [], EventSerializer.serialize(@metadata)[:tags]

      assert_equal "", EventSerializer.serialize(events(:follows))[:content]
    end

    test "handles nil nostr_created_at" do
      @text_note.nostr_created_at = nil
      assert_nil EventSerializer.serialize(@text_note)[:created_at]
    end

    # =========================================
    # Collections
    # =========================================

    test "serializes collection of events" do
      result = EventSerializer.serialize(Event.limit(3))

      assert_kind_of Array, result
      result.each do |item|
        %i[id pubkey created_at kind tags content sig].each { |key| assert item.key?(key) }
      end
    end

    test "serialize_collection class method" do
      result = EventSerializer.serialize_collection(Event.limit(2).to_a)

      assert_equal 2, result.length
      result.each { |item| assert_kind_of Hash, item }
    end

    # =========================================
    # JSON Output
    # =========================================

    test "to_json produces valid NIP-01 JSON" do
      parsed = JSON.parse(EventSerializer.new(@text_note).to_json)

      assert_equal @text_note.event_id, parsed["id"]
      assert_equal @text_note.pubkey, parsed["pubkey"]
      assert_equal @text_note.kind, parsed["kind"]
    end

    # =========================================
    # Different Event Types
    # =========================================

    test "serializes various event kinds" do
      { @metadata => 0, @reaction => 7, @long_form => 30_023 }.each do |event, kind|
        result = EventSerializer.serialize(event)
        assert_equal kind, result[:kind]
      end
    end

    test "long-form includes d-tag in tags" do
      result = EventSerializer.serialize(@long_form)
      d_tag = result[:tags].find { |t| t[0] == "d" }
      assert_not_nil d_tag
    end

    # =========================================
    # Hex Format Compliance
    # =========================================

    test "hex fields are properly formatted" do
      result = EventSerializer.serialize(@text_note)

      assert_equal 64, result[:id].length
      assert_match(/\A[a-f0-9]+\z/, result[:id])

      assert_equal 64, result[:pubkey].length
      assert_match(/\A[a-f0-9]+\z/, result[:pubkey])

      assert_equal 128, result[:sig].length
      assert_match(/\A[a-f0-9]+\z/, result[:sig])
    end
  end
end
