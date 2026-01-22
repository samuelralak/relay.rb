# frozen_string_literal: true

require "test_helper"

class EventTagTest < ActiveSupport::TestCase
  setup do
    @p_tag = event_tags(:text_note_p_tag)
    @t_tag = event_tags(:text_note_t_tag)
    @e_tag = event_tags(:reaction_e_tag)
    @d_tag = event_tags(:long_form_d_tag)
  end

  # =========================================
  # Validations
  # =========================================

  test "valid event_tag passes validation" do
    assert_valid @p_tag
  end

  test "tag_name is required and exactly 1 character" do
    @p_tag.tag_name = nil
    assert_invalid @p_tag, :tag_name, "can't be blank"

    @p_tag.tag_name = "pp"
    assert_invalid @p_tag, :tag_name

    @p_tag.tag_name = ""
    assert_invalid @p_tag, :tag_name
  end

  test "tag_value is required with max 255 characters" do
    @p_tag.tag_value = nil
    assert_invalid @p_tag, :tag_value, "can't be blank"

    @p_tag.tag_value = "a" * 256
    assert_invalid @p_tag, :tag_value

    @p_tag.tag_value = "a" * 255
    assert_valid @p_tag
  end

  test "tag_index is required and non-negative" do
    @p_tag.tag_index = nil
    assert_invalid @p_tag, :tag_index

    @p_tag.tag_index = -1
    assert_invalid @p_tag, :tag_index

    @p_tag.tag_index = 0
    assert_valid @p_tag
  end

  test "nostr_created_at and kind are required" do
    @p_tag.nostr_created_at = nil
    assert_invalid @p_tag, :nostr_created_at

    @p_tag.nostr_created_at = Time.current
    @p_tag.kind = nil
    assert_invalid @p_tag, :kind
  end

  # =========================================
  # Associations
  # =========================================

  test "belongs to event" do
    assert_instance_of Event, @p_tag.event
  end

  # =========================================
  # Identifiable
  # =========================================

  test "tag type predicates" do
    assert @e_tag.event_reference?
    assert @p_tag.pubkey_reference?
    assert @t_tag.hashtag?
    assert @d_tag.identifier_tag?
  end

  test "indexable? for single letters a-z and A-Z" do
    assert @p_tag.indexable?

    %w[a z A Z].each do |letter|
      @p_tag.tag_name = letter
      assert @p_tag.indexable?, "Expected '#{letter}' to be indexable"
    end
  end

  test "reference_tag? for e, p, a tags" do
    assert @e_tag.reference_tag?
    assert @p_tag.reference_tag?
    assert_not @t_tag.reference_tag?
  end

  # =========================================
  # Queryable Scopes - Basic
  # =========================================

  test "by_tag_name, by_tag_value, by_tag" do
    EventTag.by_tag_name("p").each { |t| assert_equal "p", t.tag_name }
    EventTag.by_tag_value(@p_tag.tag_value).each { |t| assert_equal @p_tag.tag_value, t.tag_value }

    EventTag.by_tag("p", @p_tag.tag_value).each do |t|
      assert_equal "p", t.tag_name
      assert_equal @p_tag.tag_value, t.tag_value
    end
  end

  test "by_kind and by_kinds" do
    EventTag.by_kind(1).each { |t| assert_equal 1, t.kind }
    EventTag.by_kinds([ 1, 7 ]).each { |t| assert_includes [ 1, 7 ], t.kind }
  end

  # =========================================
  # Queryable Scopes - Tag Types
  # =========================================

  test "tag type scopes" do
    { e_tags: "e", p_tags: "p", t_tags: "t", d_tags: "d" }.each do |scope, name|
      EventTag.public_send(scope).each { |t| assert_equal name, t.tag_name }
    end
  end

  # =========================================
  # Queryable Scopes - Time-Based
  # =========================================

  test "since and until_time filter by timestamp" do
    timestamp = 30.minutes.ago.to_i

    EventTag.since(timestamp).each { |t| assert t.nostr_created_at >= Time.at(timestamp).utc }
    EventTag.until_time(timestamp).each { |t| assert t.nostr_created_at <= Time.at(timestamp).utc }
  end

  test "in_time_range filters within bounds" do
    since_ts = 1.hour.ago.to_i
    until_ts = 10.minutes.ago.to_i

    EventTag.in_time_range(since_ts, until_ts).each do |t|
      assert t.nostr_created_at >= Time.at(since_ts).utc
      assert t.nostr_created_at <= Time.at(until_ts).utc
    end
  end

  # =========================================
  # Queryable Scopes - Ordering
  # =========================================

  test "ordering scopes" do
    assert_ordered_desc EventTag.newest_first.limit(5), :nostr_created_at
    assert_ordered_asc EventTag.oldest_first.limit(5), :nostr_created_at
    assert_ordered_asc events(:text_note).event_tags.by_index, :tag_index
  end

  # =========================================
  # Queryable Class Methods
  # =========================================

  test "event_ids_for_tag returns matching event IDs" do
    result = EventTag.event_ids_for_tag(tag_name: "p", tag_values: [ @p_tag.tag_value ])

    assert_kind_of Array, result
    assert result.any?
  end

  test "event_ids_for_tag respects limit and kinds" do
    result = EventTag.event_ids_for_tag(tag_name: "p", tag_values: [ @p_tag.tag_value ], limit: 1)
    assert result.count <= 1

    result = EventTag.event_ids_for_tag(tag_name: "t", tag_values: [ "nostr" ], kinds: [ 1 ])
    Event.where(id: result).each { |e| assert_equal 1, e.kind }
  end

  test "convenience methods for common tag queries" do
    assert_kind_of Array, EventTag.referencing_event(HEX_64)
    assert_kind_of Array, EventTag.referencing_pubkey(HEX_64_ALT)
  end

  test "with_hashtag normalizes input" do
    result_plain = EventTag.with_hashtag("nostr")
    result_hash = EventTag.with_hashtag("#nostr")
    result_upper = EventTag.with_hashtag("NOSTR")

    assert result_plain.any?
    assert_equal result_plain.sort, result_hash.sort
    assert_kind_of Array, result_upper
  end

  # =========================================
  # Soft Delete (Paranoia)
  # =========================================

  test "destroy soft deletes" do
    tag_id = @p_tag.id
    @p_tag.destroy

    assert_nil EventTag.find_by(id: tag_id)
    assert EventTag.with_deleted.exists?(id: tag_id)
  end

  test "deleted tags excluded by default" do
    deleted = event_tags(:deleted_tag)

    assert_not EventTag.exists?(id: deleted.id)
    assert EventTag.with_deleted.exists?(id: deleted.id)
  end

  test "only_deleted returns deleted tags" do
    EventTag.only_deleted.each { |t| assert_not_nil t.deleted_at }
  end
end
