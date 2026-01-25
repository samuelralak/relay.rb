# frozen_string_literal: true

require "test_helper"

module Events
  class ProcessDeletionJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    # =========================================================================
    # Queue Configuration
    # =========================================================================

    test "job is enqueued to deletions queue" do
      assert_equal "deletions", ProcessDeletionJob.new.queue_name
    end

    # =========================================================================
    # E-tag Deletion (Event IDs)
    # =========================================================================

    test "soft-deletes target by e-tag" do
      target_event = events(:text_note)
      deletion_event = create_deletion_event(
        pubkey: target_event.pubkey,
        tags: [["e", target_event.event_id]]
      )

      ProcessDeletionJob.new.perform(deletion_event.id)

      # Event should be soft-deleted
      assert_nil Event.find_by(event_id: target_event.event_id)
      assert Event.with_deleted.exists?(event_id: target_event.event_id)
    end

    test "does not delete events from different pubkey" do
      target_event = events(:other_author_note)
      deletion_event = create_deletion_event(
        pubkey: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", # Different from target
        tags: [["e", target_event.event_id]]
      )

      ProcessDeletionJob.new.perform(deletion_event.id)

      # Event should NOT be deleted (different pubkey)
      assert Event.exists?(event_id: target_event.event_id)
    end

    test "cannot delete deletion requests (kind 5)" do
      # Create a deletion event
      first_deletion = create_deletion_event(
        pubkey: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        tags: []
      )

      # Try to delete the deletion
      second_deletion = create_deletion_event(
        pubkey: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        tags: [["e", first_deletion.event_id]]
      )

      ProcessDeletionJob.new.perform(second_deletion.id)

      # Original deletion should still exist (kind 5 cannot be deleted)
      assert Event.exists?(event_id: first_deletion.event_id)
    end

    test "deletes multiple events from e-tags" do
      pubkey = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

      # Create multiple events
      event1 = create_event(pubkey:, kind: 1, content: "Event 1")
      event2 = create_event(pubkey:, kind: 1, content: "Event 2")

      deletion_event = create_deletion_event(
        pubkey:,
        tags: [["e", event1.event_id], ["e", event2.event_id]]
      )

      ProcessDeletionJob.new.perform(deletion_event.id)

      # Both events should be soft-deleted
      assert_nil Event.find_by(event_id: event1.event_id)
      assert_nil Event.find_by(event_id: event2.event_id)
    end

    # =========================================================================
    # A-tag Deletion (Addressable Events)
    # =========================================================================

    test "deletes addressable event by a-tag" do
      target_event = events(:long_form)
      coordinate = "#{target_event.kind}:#{target_event.pubkey}:#{target_event.d_tag}"

      deletion_event = create_deletion_event(
        pubkey: target_event.pubkey,
        tags: [["a", coordinate]]
      )

      ProcessDeletionJob.new.perform(deletion_event.id)

      # Event should be soft-deleted
      assert_nil Event.find_by(event_id: target_event.event_id)
    end

    test "a-tag deletion respects created_at boundary" do
      pubkey = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

      # Create older version
      older_event = create_event(
        pubkey:,
        kind: 30023,
        d_tag: "test-article",
        nostr_created_at: 2.hours.ago
      )

      # Create newer version
      newer_event = create_event(
        pubkey:,
        kind: 30023,
        d_tag: "test-article",
        nostr_created_at: 1.minute.ago
      )

      # Deletion request from 1 hour ago
      deletion_event = create_deletion_event(
        pubkey:,
        created_at: 1.hour.ago.to_i,
        tags: [["a", "30023:#{pubkey}:test-article"]]
      )

      ProcessDeletionJob.new.perform(deletion_event.id)

      # Only older version should be deleted (created before deletion timestamp)
      assert_nil Event.find_by(event_id: older_event.event_id)
      assert Event.exists?(event_id: newer_event.event_id)
    end

    test "a-tag deletion only affects matching pubkey" do
      target_pubkey = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      attacker_pubkey = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

      target_event = create_event(
        pubkey: target_pubkey,
        kind: 30023,
        d_tag: "my-article"
      )

      # Attacker tries to delete someone else's event
      deletion_event = create_deletion_event(
        pubkey: attacker_pubkey,
        tags: [["a", "30023:#{target_pubkey}:my-article"]]
      )

      ProcessDeletionJob.new.perform(deletion_event.id)

      # Target event should NOT be deleted (attacker pubkey != coordinate pubkey)
      assert Event.exists?(event_id: target_event.event_id)
    end

    # =========================================================================
    # Edge Cases
    # =========================================================================

    test "handles missing deletion event gracefully" do
      assert_nothing_raised do
        ProcessDeletionJob.new.perform("non-existent-uuid")
      end
    end

    test "handles empty tags array" do
      deletion_event = create_deletion_event(tags: [])

      assert_nothing_raised do
        ProcessDeletionJob.new.perform(deletion_event.id)
      end
    end

    test "handles malformed a-tag coordinate" do
      deletion_event = create_deletion_event(
        tags: [["a", "invalid-coordinate"]]
      )

      assert_nothing_raised do
        ProcessDeletionJob.new.perform(deletion_event.id)
      end
    end

    test "handles event with empty tags gracefully" do
      # Tags can be empty but not nil (database constraint)
      deletion_event = create_deletion_event(tags: [])

      assert_nothing_raised do
        ProcessDeletionJob.new.perform(deletion_event.id)
      end
    end

    # =========================================================================
    # Helpers
    # =========================================================================

    private

    def create_event(pubkey:, kind:, content: "Test", d_tag: nil, nostr_created_at: Time.current)
      Event.create!(
        event_id: SecureRandom.hex(32),
        pubkey:,
        nostr_created_at:,
        kind:,
        tags: d_tag ? [["d", d_tag]] : [],
        content:,
        sig: SecureRandom.hex(64),
        raw_event: "{}",
        d_tag:,
        first_seen_at: Time.current
      )
    end

    def create_deletion_event(pubkey: nil, tags: [], created_at: Time.current.to_i)
      Event.create!(
        event_id: SecureRandom.hex(32),
        pubkey: pubkey || "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        nostr_created_at: Time.at(created_at),
        kind: 5,
        tags: tags || [],
        content: "deleted",
        sig: SecureRandom.hex(64),
        raw_event: "{}",
        first_seen_at: Time.current
      )
    end
  end
end
