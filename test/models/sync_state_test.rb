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
    filter = @sync_state.download_filter({ kinds: [1] })

    assert_equal [1], filter[:kinds]
    assert_equal 1000, filter[:since]
  end

  test "download_filter returns filter without since when no timestamp" do
    @sync_state.last_download_timestamp = nil
    filter = @sync_state.download_filter({ kinds: [1] })

    assert_equal [1], filter[:kinds]
    assert_not filter.key?(:since)
  end

  test "total_events_synced returns sum of downloaded and uploaded" do
    @sync_state.events_downloaded = 100
    @sync_state.events_uploaded = 50

    assert_equal 150, @sync_state.total_events_synced
  end
end
