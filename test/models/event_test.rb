# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @text_note = events(:text_note)
    @metadata = events(:metadata)
    @follows = events(:follows)
    @long_form = events(:long_form)
  end

  # =========================================
  # Validations
  # =========================================

  test "valid event passes validation" do
    assert_valid @text_note
  end

  test "event_id is required, 64-char lowercase hex, unique" do
    @text_note.event_id = nil
    assert_invalid @text_note, :event_id, "can't be blank"

    @text_note.event_id = INVALID_HEX_TOO_SHORT
    assert_invalid @text_note, :event_id

    @text_note.event_id = INVALID_HEX_UPPERCASE
    assert_invalid @text_note, :event_id, "must be lowercase hex"

    # Uniqueness
    duplicate = Event.new(build_event_attrs(event_id: events(:metadata).event_id))
    assert_invalid duplicate, :event_id, "has already been taken"
  end

  test "pubkey is required, 64-char lowercase hex" do
    @text_note.pubkey = nil
    assert_invalid @text_note, :pubkey

    @text_note.pubkey = INVALID_HEX_TOO_SHORT
    assert_invalid @text_note, :pubkey

    @text_note.pubkey = INVALID_HEX_UPPERCASE
    assert_invalid @text_note, :pubkey, "must be lowercase hex"
  end

  test "sig is required, 128-char lowercase hex" do
    @text_note.sig = "d" * 127
    assert_invalid @text_note, :sig

    @text_note.sig = "D" * 128
    assert_invalid @text_note, :sig, "must be lowercase hex"
  end

  test "kind must be 0-65535" do
    [ -1, 65536 ].each do |invalid_kind|
      @text_note.kind = invalid_kind
      assert_invalid @text_note, :kind
    end

    [ 0, 65535 ].each do |valid_kind|
      @text_note.kind = valid_kind
      assert_valid @text_note
    end
  end

  test "nostr_created_at and raw_event are required" do
    event = Event.new
    assert_not event.valid?
    # Note: tags has DB default [] so it's always a valid array
    %i[nostr_created_at raw_event].each do |attr|
      assert event.errors[attr].any?, "Expected error on #{attr}"
    end
  end

  test "tags must be an array" do
    # Test nil tags (before_validation callbacks may run on reload, so test directly)
    event = Event.new(build_event_attrs(tags: nil))
    event.tags = nil  # Force nil after attrs set
    assert_not event.valid?
    assert event.errors[:tags].any?, "Expected error on tags when nil"

    # Empty array is valid per Nostr spec
    @text_note.tags = []
    assert_valid @text_note
  end

  test "content can be blank" do
    @text_note.content = ""
    assert_valid @text_note
  end

  # =========================================
  # Associations
  # =========================================

  test "has many event_tags with dependent delete" do
    assert @text_note.event_tags.any?

    @text_note.really_destroy!
    assert_equal 0, EventTag.where(event_id: @text_note.id).count
  end

  # =========================================
  # Kind Classification (Classifiable)
  # =========================================

  test "classifies regular events" do
    assert @text_note.regular?
    assert_not @text_note.replaceable?
    assert_not @text_note.ephemeral?
    assert_not @text_note.addressable?
    assert_equal :regular, @text_note.classification
  end

  test "classifies replaceable events" do
    [ @metadata, @follows ].each do |event|
      assert event.replaceable?
      assert_not event.regular?
      assert_equal :replaceable, event.classification
    end
  end

  test "classifies addressable events" do
    assert @long_form.addressable?
    assert @long_form.parameterized_replaceable?
    assert_equal :addressable, @long_form.classification
  end

  test "storable? is true for non-ephemeral events" do
    [ @text_note, @metadata, @long_form ].each { |e| assert e.storable? }
  end

  # =========================================
  # Kind-Based Scopes
  # =========================================

  test "kind scopes filter correctly" do
    { text_notes: 1, metadata_events: 0, reactions: 7 }.each do |scope, kind|
      Event.public_send(scope).each { |e| assert_equal kind, e.kind }
    end
  end

  # =========================================
  # Expiration (Expirable)
  # =========================================

  test "expired? checks expiration timestamp" do
    assert events(:expired_event).expired?
    assert_not @text_note.expired?
  end

  test "not_expired scope excludes expired events" do
    Event.not_expired.each { |e| assert_not e.expired? }
  end

  test "created_at_unix converts to/from unix timestamp" do
    assert_kind_of Integer, @text_note.created_at_unix
    assert_equal @text_note.nostr_created_at.to_i, @text_note.created_at_unix

    event = Event.new
    event.created_at_unix = Time.current.to_i
    assert_kind_of Time, event.nostr_created_at
  end

  test "first_seen_at is set automatically on create" do
    event = Event.new(build_event_attrs)
    assert_nil event.first_seen_at
    event.save!
    assert_not_nil event.first_seen_at
  end

  # =========================================
  # Tag Extraction (Taggable)
  # =========================================

  test "d_tag extracted for addressable events only" do
    assert_equal "my-article", @long_form.d_tag
    assert_nil @text_note.d_tag
  end

  test "event_tags created from tags array" do
    event = create_event(tags: [ [ "p", HEX_64 ], [ "t", "test" ] ])

    assert_equal 2, event.event_tags.count
    assert event.event_tags.exists?(tag_name: "p", tag_value: HEX_64)
    assert event.event_tags.exists?(tag_name: "t", tag_value: "test")
  end

  test "only valid single-letter tags are indexed" do
    event = create_event(
      tags: [
        [ "p", HEX_64 ],                      # valid
        [ "content-warning", "nsfw" ],        # multi-char name - skip
        [ "t", "a" * 256 ],                   # value too long - skip
        [ "e", 123 ],                         # non-string value - skip
        [ "r", "https://example.com" ]        # valid
      ]
    )
    assert_equal 2, event.event_tags.count
  end

  # =========================================
  # Filtering (Filterable)
  # =========================================

  test "by_event_ids filters by ID" do
    ids = [ @text_note.event_id, @metadata.event_id ]
    results = Event.by_event_ids(ids)

    assert_equal 2, results.count
    results.each { |e| assert_includes ids, e.event_id }
  end

  test "by_authors filters by pubkey" do
    results = Event.by_authors([ @text_note.pubkey ])
    results.each { |e| assert_equal @text_note.pubkey, e.pubkey }
  end

  test "by_kinds filters by kind" do
    results = Event.by_kinds([ 1, 7 ])
    results.each { |e| assert_includes [ 1, 7 ], e.kind }
  end

  test "since and until_time filter by timestamp" do
    timestamp = 30.minutes.ago.to_i

    Event.since(timestamp).each do |e| assert e.nostr_created_at >= Time.at(timestamp).utc end
    Event.until_time(timestamp).each { |e| assert e.nostr_created_at <= Time.at(timestamp).utc }
  end

  test "ordering scopes" do
    assert_ordered_desc Event.newest_first.limit(5), :nostr_created_at
    assert_ordered_asc Event.oldest_first.limit(5), :nostr_created_at
  end

  test "scopes return all records when given nil" do
    total = Event.count
    assert_equal total, Event.by_event_ids(nil).count
    assert_equal total, Event.by_authors(nil).count
    assert_equal total, Event.by_kinds(nil).count
  end

  # =========================================
  # Find Methods
  # =========================================

  test "find_replaceable finds by pubkey and kind" do
    found = Event.find_replaceable(pubkey: @metadata.pubkey, kind: 0)
    assert_equal @metadata.id, found.id
  end

  test "find_addressable finds by pubkey, kind, and d_tag" do
    found = Event.find_addressable(pubkey: @long_form.pubkey, kind: 30023, d_tag: "my-article")
    assert_equal @long_form.id, found.id
  end

  # =========================================
  # Matching Filter
  # =========================================

  test "matching_filter combines filters" do
    results = Event.matching_filter(authors: [ @text_note.pubkey ], kinds: [ 1 ], limit: 10)

    results.each do |e|
      assert_equal @text_note.pubkey, e.pubkey
      assert_equal 1, e.kind
    end
    assert results.count <= 10
  end

  test "matching_filter handles tag filters" do
    results = Event.matching_filter("#t": [ "nostr" ], kinds: [ 1 ])

    assert results.exists?
    results.each { |e| assert e.event_tags.exists?(tag_name: "t", tag_value: "nostr") }
  end

  test "matching_filter excludes expired events" do
    Event.matching_filter(kinds: [ 1 ]).each { |e| assert_not e.expired? }
  end

  test "matches_filter? returns false for expired events" do
    expired = events(:expired_event)
    filter = { kinds: [ 1 ] }

    assert_not expired.matches_filter?(filter)
  end

  test "matches_filter? returns true for non-expired events" do
    event = events(:text_note)
    filter = { kinds: [ 1 ] }

    assert event.matches_filter?(filter)
  end

  # =========================================
  # Soft Delete (Paranoia)
  # =========================================

  test "destroy soft deletes" do
    event_id = @text_note.id
    @text_note.destroy

    assert_nil Event.find_by(id: event_id)
    assert Event.with_deleted.exists?(id: event_id)
  end

  test "deleted events excluded by default" do
    deleted = events(:deleted_event)

    assert_not Event.exists?(id: deleted.id)
    assert Event.with_deleted.exists?(id: deleted.id)
  end

  test "only_deleted returns deleted events" do
    Event.only_deleted.each { |e| assert_not_nil e.deleted_at }
  end
end
