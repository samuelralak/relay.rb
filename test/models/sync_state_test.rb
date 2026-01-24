# frozen_string_literal: true

require "test_helper"

class SyncStateTest < ActiveSupport::TestCase
  setup do
    @sync_state = SyncState.new(
      relay_url: "wss://test.relay.com",
      direction: "down",
      filter_hash: "test_filter"
    )
  end

  # Validations
  test "valid with required attributes" do
    assert @sync_state.valid?
  end

  test "invalid without relay_url" do
    @sync_state.relay_url = nil
    assert_not @sync_state.valid?
    assert_includes @sync_state.errors[:relay_url], "can't be blank"
  end

  test "invalid with invalid status" do
    @sync_state.status = "invalid_status"
    assert_not @sync_state.valid?
    assert_includes @sync_state.errors[:status], "is not included in the list"
  end

  test "invalid with invalid direction" do
    @sync_state.direction = "invalid_direction"
    assert_not @sync_state.valid?
    assert_includes @sync_state.errors[:direction], "is not included in the list"
  end

  test "invalid with negative events_downloaded" do
    @sync_state.events_downloaded = -1
    assert_not @sync_state.valid?
    assert_includes @sync_state.errors[:events_downloaded], "must be greater than or equal to 0"
  end

  test "invalid with negative events_uploaded" do
    @sync_state.events_uploaded = -1
    assert_not @sync_state.valid?
    assert_includes @sync_state.errors[:events_uploaded], "must be greater than or equal to 0"
  end

  test "enforces uniqueness on relay_url and filter_hash" do
    @sync_state.save!
    duplicate = SyncState.new(
      relay_url: @sync_state.relay_url,
      direction: "up",
      filter_hash: @sync_state.filter_hash
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:relay_url], "has already been taken"
  end

  # Scopes
  test "for_relay scope" do
    @sync_state.save!
    other = SyncState.create!(relay_url: "wss://other.relay.com", direction: "down", filter_hash: "other")

    results = SyncState.for_relay("wss://test.relay.com")
    assert_includes results, @sync_state
    assert_not_includes results, other
  end

  test "active scope includes idle and syncing" do
    idle = SyncState.create!(relay_url: "wss://idle.relay.com", direction: "down", filter_hash: "idle", status: "idle")
    syncing = SyncState.create!(relay_url: "wss://syncing.relay.com", direction: "down", filter_hash: "syncing", status: "syncing")
    completed = SyncState.create!(relay_url: "wss://completed.relay.com", direction: "down", filter_hash: "completed", status: "completed")
    error = SyncState.create!(relay_url: "wss://error.relay.com", direction: "down", filter_hash: "error", status: "error")

    active = SyncState.active
    assert_includes active, idle
    assert_includes active, syncing
    assert_not_includes active, completed
    assert_not_includes active, error
  end

  test "downloads scope includes down and both" do
    down = SyncState.create!(relay_url: "wss://down.relay.com", direction: "down", filter_hash: "down")
    up = SyncState.create!(relay_url: "wss://up.relay.com", direction: "up", filter_hash: "up")
    both = SyncState.create!(relay_url: "wss://both.relay.com", direction: "both", filter_hash: "both")

    downloads = SyncState.downloads
    assert_includes downloads, down
    assert_not_includes downloads, up
    assert_includes downloads, both
  end

  test "uploads scope includes up and both" do
    down = SyncState.create!(relay_url: "wss://down.relay.com", direction: "down", filter_hash: "down")
    up = SyncState.create!(relay_url: "wss://up.relay.com", direction: "up", filter_hash: "up")
    both = SyncState.create!(relay_url: "wss://both.relay.com", direction: "both", filter_hash: "both")

    uploads = SyncState.uploads
    assert_not_includes uploads, down
    assert_includes uploads, up
    assert_includes uploads, both
  end

  # State transitions
  test "mark_syncing! updates status and clears error" do
    @sync_state.save!
    @sync_state.update!(status: "error", error_message: "Some error")

    @sync_state.mark_syncing!

    assert_equal "syncing", @sync_state.status
    assert_nil @sync_state.error_message
  end

  test "mark_download_progress! updates download tracking" do
    @sync_state.save!
    original_count = @sync_state.events_downloaded

    freeze_time do
      @sync_state.mark_download_progress!(event_id: "abc123", timestamp: Time.current)

      assert_equal "abc123", @sync_state.last_download_event_id
      assert_equal Time.current, @sync_state.last_download_timestamp
      assert_equal Time.current, @sync_state.last_synced_at
      assert_equal original_count + 1, @sync_state.events_downloaded
    end
  end

  test "mark_download_progress! with count increments by count" do
    @sync_state.save!
    @sync_state.mark_download_progress!(event_id: "abc123", timestamp: Time.current, count: 5)

    assert_equal 5, @sync_state.events_downloaded
  end

  test "mark_upload_progress! updates upload tracking" do
    @sync_state.save!
    original_count = @sync_state.events_uploaded

    freeze_time do
      @sync_state.mark_upload_progress!(event_id: "xyz789", timestamp: Time.current)

      assert_equal "xyz789", @sync_state.last_upload_event_id
      assert_equal Time.current, @sync_state.last_upload_timestamp
      assert_equal Time.current, @sync_state.last_synced_at
      assert_equal original_count + 1, @sync_state.events_uploaded
    end
  end

  test "mark_completed! updates status" do
    @sync_state.save!
    @sync_state.update!(status: "syncing")

    @sync_state.mark_completed!

    assert_equal "completed", @sync_state.status
    assert_nil @sync_state.error_message
  end

  test "mark_error! updates status and message" do
    @sync_state.save!

    @sync_state.mark_error!("Connection failed")

    assert_equal "error", @sync_state.status
    assert_equal "Connection failed", @sync_state.error_message
  end

  test "reset_to_idle! resets status" do
    @sync_state.save!
    @sync_state.update!(status: "error", error_message: "Some error")

    @sync_state.reset_to_idle!

    assert_equal "idle", @sync_state.status
    assert_nil @sync_state.error_message
  end

  # Direction helpers
  test "download_enabled? returns true for down direction" do
    @sync_state.direction = "down"
    assert @sync_state.download_enabled?
  end

  test "download_enabled? returns true for both direction" do
    @sync_state.direction = "both"
    assert @sync_state.download_enabled?
  end

  test "download_enabled? returns false for up direction" do
    @sync_state.direction = "up"
    assert_not @sync_state.download_enabled?
  end

  test "upload_enabled? returns true for up direction" do
    @sync_state.direction = "up"
    assert @sync_state.upload_enabled?
  end

  test "upload_enabled? returns true for both direction" do
    @sync_state.direction = "both"
    assert @sync_state.upload_enabled?
  end

  test "upload_enabled? returns false for down direction" do
    @sync_state.direction = "down"
    assert_not @sync_state.upload_enabled?
  end

  # Status helpers
  test "idle? returns true when status is idle" do
    @sync_state.status = "idle"
    assert @sync_state.idle?
  end

  test "syncing? returns true when status is syncing" do
    @sync_state.status = "syncing"
    assert @sync_state.syncing?
  end

  test "error? returns true when status is error" do
    @sync_state.status = "error"
    assert @sync_state.error?
  end

  # Filter and query methods
  test "download_filter returns filter with since when timestamp exists" do
    @sync_state.last_download_timestamp = Time.at(1000)
    filter = @sync_state.download_filter({ kinds: [ 1 ] })

    assert_equal [ 1 ], filter[:kinds]
    assert_equal 1000, filter[:since]
  end

  test "download_filter returns filter without since when no timestamp" do
    @sync_state.last_download_timestamp = nil
    filter = @sync_state.download_filter({ kinds: [ 1 ] })

    assert_equal [ 1 ], filter[:kinds]
    assert_not filter.key?(:since)
  end

  test "total_events_synced returns sum of downloaded and uploaded" do
    @sync_state.events_downloaded = 100
    @sync_state.events_uploaded = 50

    assert_equal 150, @sync_state.total_events_synced
  end

  # Class methods - compute_filter_hash
  test "compute_filter_hash produces consistent hash for same inputs" do
    hash1 = SyncState.compute_filter_hash(direction: "down", filter: { kinds: [1, 3] })
    hash2 = SyncState.compute_filter_hash(direction: "down", filter: { kinds: [1, 3] })

    assert_equal hash1, hash2
  end

  test "compute_filter_hash ignores since and until in filter" do
    hash1 = SyncState.compute_filter_hash(direction: "down", filter: { kinds: [1] })
    hash2 = SyncState.compute_filter_hash(direction: "down", filter: { kinds: [1], since: 12345, until: 67890 })

    assert_equal hash1, hash2
  end

  test "compute_filter_hash differs by direction" do
    hash_down = SyncState.compute_filter_hash(direction: "down", filter: {})
    hash_up = SyncState.compute_filter_hash(direction: "up", filter: {})

    assert_not_equal hash_down, hash_up
  end

  test "compute_filter_hash differs by filter content" do
    hash1 = SyncState.compute_filter_hash(direction: "down", filter: { kinds: [1] })
    hash2 = SyncState.compute_filter_hash(direction: "down", filter: { kinds: [1, 3] })

    assert_not_equal hash1, hash2
  end

  test "compute_filter_hash handles empty filter" do
    hash = SyncState.compute_filter_hash(direction: "down", filter: {})

    assert_kind_of String, hash
    assert_equal 16, hash.length
  end

  test "compute_filter_hash normalizes key order" do
    hash1 = SyncState.compute_filter_hash(direction: "down", filter: { kinds: [1], authors: ["abc"] })
    hash2 = SyncState.compute_filter_hash(direction: "down", filter: { authors: ["abc"], kinds: [1] })

    assert_equal hash1, hash2
  end

  # Class methods - for_sync
  test "for_sync creates new record when none exists" do
    assert_difference "SyncState.count", 1 do
      state = SyncState.for_sync(relay_url: "wss://new.relay.com", direction: "down", filter: {})

      assert_equal "wss://new.relay.com", state.relay_url
      assert_equal "down", state.direction
      assert_equal "idle", state.status
      assert_equal 0, state.events_downloaded
      assert_equal 0, state.events_uploaded
    end
  end

  test "for_sync returns existing record when one exists" do
    existing = SyncState.for_sync(relay_url: "wss://existing.relay.com", direction: "down", filter: {})

    assert_no_difference "SyncState.count" do
      found = SyncState.for_sync(relay_url: "wss://existing.relay.com", direction: "down", filter: {})
      assert_equal existing.id, found.id
    end
  end

  test "for_sync uses consistent filter_hash" do
    state1 = SyncState.for_sync(relay_url: "wss://test.relay.com", direction: "down", filter: { since: 100 })
    state2 = SyncState.for_sync(relay_url: "wss://test.relay.com", direction: "down", filter: { since: 200 })

    # Should be same record because since is excluded from hash
    assert_equal state1.id, state2.id
  end

  test "for_sync handles race condition gracefully" do
    # Simulate a race condition by creating a record directly, then calling for_sync
    # which would normally try to create (and fail), but should recover by finding
    filter_hash = SyncState.compute_filter_hash(direction: "down", filter: {})

    # Create the record directly (simulating another process winning the race)
    existing = SyncState.create!(
      relay_url: "wss://race.relay.com",
      direction: "down",
      filter_hash: filter_hash,
      status: "idle",
      events_downloaded: 0,
      events_uploaded: 0
    )

    # Now for_sync should find it (not raise RecordNotUnique)
    found = SyncState.for_sync(relay_url: "wss://race.relay.com", direction: "down", filter: {})

    assert_equal existing.id, found.id
  end

  # completed? helper
  test "completed? returns true when status is completed" do
    @sync_state.status = "completed"
    assert @sync_state.completed?
  end

  test "completed? returns false when status is not completed" do
    @sync_state.status = "syncing"
    assert_not @sync_state.completed?
  end

  # Atomic increment methods
  test "increment_events_downloaded! atomically increments counter" do
    @sync_state.save!
    original = @sync_state.events_downloaded

    @sync_state.increment_events_downloaded!(10)

    assert_equal original + 10, @sync_state.events_downloaded
  end

  test "increment_events_downloaded! does nothing for zero or negative" do
    @sync_state.save!
    original = @sync_state.events_downloaded

    @sync_state.increment_events_downloaded!(0)
    assert_equal original, @sync_state.events_downloaded

    @sync_state.increment_events_downloaded!(-5)
    assert_equal original, @sync_state.events_downloaded
  end

  test "increment_events_uploaded! atomically increments counter" do
    @sync_state.save!
    original = @sync_state.events_uploaded

    @sync_state.increment_events_uploaded!(15)

    assert_equal original + 15, @sync_state.events_uploaded
  end

  # Stale detection
  test "stale? returns true when syncing and updated_at is old" do
    @sync_state.save!
    @sync_state.update!(status: "syncing", updated_at: 10.minutes.ago)

    assert @sync_state.stale?(threshold: 5.minutes)
  end

  test "stale? returns false when syncing but recently updated" do
    @sync_state.save!
    @sync_state.update!(status: "syncing", updated_at: 1.minute.ago)

    assert_not @sync_state.stale?(threshold: 5.minutes)
  end

  test "stale? returns false when not syncing" do
    @sync_state.save!
    @sync_state.update!(status: "idle", updated_at: 10.minutes.ago)

    assert_not @sync_state.stale?(threshold: 5.minutes)
  end

  # Resume filter
  test "resume_filter uses last_download_timestamp when present" do
    @sync_state.last_download_timestamp = Time.at(1000)

    filter = @sync_state.resume_filter(base_filter: { kinds: [1] }, overlap_seconds: 60)

    assert_equal [1], filter[:kinds]
    assert_equal 940, filter[:since]  # 1000 - 60
  end

  test "resume_filter uses fallback_since when no timestamp" do
    @sync_state.last_download_timestamp = nil

    filter = @sync_state.resume_filter(base_filter: {}, fallback_since: 500)

    assert_equal 500, filter[:since]
  end

  test "resume_filter returns filter without since when no timestamp and no fallback" do
    @sync_state.last_download_timestamp = nil

    filter = @sync_state.resume_filter(base_filter: { kinds: [1] })

    assert_equal [1], filter[:kinds]
    assert_not filter.key?(:since)
  end

  # Resumable
  test "resumable? returns true when last_download_timestamp present" do
    @sync_state.last_download_timestamp = Time.current

    assert @sync_state.resumable?
  end

  test "resumable? returns true when last_upload_timestamp present" do
    @sync_state.last_upload_timestamp = Time.current

    assert @sync_state.resumable?
  end

  test "resumable? returns false when no timestamps" do
    @sync_state.last_download_timestamp = nil
    @sync_state.last_upload_timestamp = nil

    assert_not @sync_state.resumable?
  end

  # Backfill tracking
  test "initialize_backfill! sets target and until timestamps" do
    @sync_state.save!
    target = 1.year.ago

    freeze_time do
      @sync_state.initialize_backfill!(target: target)

      assert_equal target.to_i, @sync_state.backfill_target.to_i
      assert_equal Time.current.to_i, @sync_state.backfill_until.to_i
    end
  end

  test "initialize_backfill! does nothing if already initialized" do
    @sync_state.save!
    original_target = 1.year.ago
    @sync_state.update!(backfill_target: original_target, backfill_until: Time.current)

    new_target = 2.years.ago
    @sync_state.initialize_backfill!(target: new_target)

    assert_equal original_target.to_i, @sync_state.backfill_target.to_i
  end

  test "next_backfill_chunk returns correct time window" do
    @sync_state.save!
    target = Time.current - 30.days
    @sync_state.update!(backfill_target: target, backfill_until: Time.current)

    chunk = @sync_state.next_backfill_chunk(chunk_hours: 168)  # 1 week

    assert_kind_of Hash, chunk
    assert chunk[:since] < chunk[:until]
    assert_equal 168 * 3600, chunk[:until] - chunk[:since]  # exactly 1 week
  end

  test "next_backfill_chunk clamps to target" do
    @sync_state.save!
    # Target is 10 days ago, backfill_until is 3 days ago
    # With 168 hour (7 day) chunks, chunk_start would be 10 days ago
    # But that's before target, so it should clamp to target
    target = 10.days.ago
    @sync_state.update!(backfill_target: target, backfill_until: 3.days.ago)

    chunk = @sync_state.next_backfill_chunk(chunk_hours: 168)  # 1 week

    # chunk_start should be clamped to target, not go past it
    assert_equal target.to_i, chunk[:since]
  end

  test "next_backfill_chunk returns nil when backfill complete" do
    @sync_state.save!
    target = 1.week.ago
    @sync_state.update!(backfill_target: target, backfill_until: target - 1.hour)

    chunk = @sync_state.next_backfill_chunk(chunk_hours: 168)

    assert_nil chunk
  end

  test "mark_backfill_chunk_completed! updates backfill_until" do
    @sync_state.save!
    @sync_state.update!(backfill_target: 1.month.ago, backfill_until: Time.current)

    chunk_start = 1.week.ago
    @sync_state.mark_backfill_chunk_completed!(chunk_start: chunk_start)

    assert_equal chunk_start.to_i, @sync_state.backfill_until.to_i
  end

  test "backfill_complete? returns true when until equals target" do
    @sync_state.save!
    target = 1.week.ago
    @sync_state.update!(backfill_target: target, backfill_until: target)

    assert @sync_state.backfill_complete?
  end

  test "backfill_complete? returns true when until is before target" do
    @sync_state.save!
    target = 1.week.ago
    @sync_state.update!(backfill_target: target, backfill_until: target - 1.day)

    assert @sync_state.backfill_complete?
  end

  test "backfill_complete? returns false when until is after target" do
    @sync_state.save!
    target = 1.week.ago
    @sync_state.update!(backfill_target: target, backfill_until: Time.current)

    assert_not @sync_state.backfill_complete?
  end

  test "backfill_complete? returns false when not initialized" do
    @sync_state.backfill_target = nil
    @sync_state.backfill_until = nil

    assert_not @sync_state.backfill_complete?
  end

  test "backfill_progress_percent returns 0 when not initialized" do
    @sync_state.backfill_target = nil
    @sync_state.backfill_until = nil

    assert_equal 0, @sync_state.backfill_progress_percent
  end

  test "backfill_progress_percent returns 100 when complete" do
    @sync_state.save!
    target = 1.week.ago
    @sync_state.update!(backfill_target: target, backfill_until: target)

    assert_equal 100, @sync_state.backfill_progress_percent
  end

  test "backfill_progress_percent calculates correct percentage" do
    @sync_state.save!
    # Target is 10 days ago, until is 5 days ago = 50% complete
    target = 10.days.ago
    until_time = 5.days.ago
    @sync_state.update!(backfill_target: target, backfill_until: until_time)

    progress = @sync_state.backfill_progress_percent

    # Should be approximately 50% (may vary slightly due to timing)
    assert_in_delta 50, progress, 1
  end
end
