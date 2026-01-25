# frozen_string_literal: true

module SyncStates
  # Handles progressive backfill tracking.
  module BackfillTrackable
    extend ActiveSupport::Concern

    # Initialize backfill tracking with a target timestamp.
    # @param target [Time] the oldest timestamp to backfill to
    def initialize_backfill!(target:)
      return if backfill_target.present? # Already initialized

      update!(
        backfill_target: target,
        backfill_until: Time.current  # Start from now and work backwards
      )
    end

    # Get the next chunk window for backfill.
    # @param chunk_hours [Integer] size of each chunk in hours
    # @return [Hash] { since:, until: } or nil if backfill complete
    def next_backfill_chunk(chunk_hours:)
      return nil if backfill_complete?

      chunk_end = backfill_until || Time.current
      chunk_start = chunk_end - chunk_hours.hours

      # Don't go past the target
      chunk_start = backfill_target if chunk_start < backfill_target

      { since: chunk_start.to_i, until: chunk_end.to_i }
    end

    # Mark a backfill chunk as completed.
    # @param chunk_start [Time] the start of the completed chunk
    def mark_backfill_chunk_completed!(chunk_start:)
      update!(backfill_until: chunk_start)
    end

    # Check if backfill has reached the target.
    def backfill_complete?
      return false unless backfill_target && backfill_until

      backfill_until <= backfill_target
    end

    # Progress percentage for backfill.
    def backfill_progress_percent
      return 100 if backfill_complete?
      return 0 unless backfill_target && backfill_until

      total_duration = Time.current - backfill_target
      return 0 if total_duration <= 0 # Guard against division by zero

      completed_duration = Time.current - backfill_until
      ((completed_duration / total_duration) * 100).round(1)
    end

    # -------------------------------------------------------------------------
    # Polling Backfill (forward direction: target → now)
    # Used by PollingJob for non-negentropy relays
    # -------------------------------------------------------------------------

    # Initialize polling backfill (forward direction).
    # @param from [Time] the oldest timestamp to start backfilling from
    def initialize_polling_backfill!(from:)
      # If already initialized with correct forward direction, skip
      if backfill_target.present?
        # Detect wrong direction: backfill_until was set near Time.current (backwards init)
        # but should be at backfill_target for forward sync.
        # Only reset if:
        # 1. Sync is not already complete (polling_backfill_complete? is false)
        # 2. backfill_until is very close to now (within 2 hours) - suggests just initialized
        # 3. backfill_target is significantly in the past (> 1 week) - meaningful backfill
        if backfill_until &&
           !polling_backfill_complete? &&
           backfill_until > Time.current - 2.hours &&
           backfill_target < Time.current - 1.week
          Rails.logger.info "[BackfillTrackable] Reinitializing #{relay_url} for forward sync " \
                            "(was: #{backfill_until}, resetting to: #{backfill_target})"
          update!(backfill_until: backfill_target)
        end
        return
      end

      update!(
        backfill_target: from,  # The oldest point (where we started)
        backfill_until: from    # Current progress (starts at oldest, moves forward)
      )
    end

    # Get next chunk moving FORWARD in time.
    # @param chunk_hours [Integer] size of each chunk in hours
    # @return [Hash] { since:, until: } or nil if backfill complete
    def next_polling_backfill_chunk(chunk_hours:)
      return nil if polling_backfill_complete?

      chunk_start = backfill_until
      return nil unless chunk_start

      chunk_end = chunk_start + chunk_hours.hours
      # Cap at current time (don't request future events)
      chunk_end = Time.current if chunk_end > Time.current

      { since: chunk_start.to_i, until: chunk_end.to_i }
    end

    # Mark a polling backfill chunk as completed.
    # @param chunk_end [Time] the end time of the completed chunk
    def mark_polling_chunk_completed!(chunk_end:)
      update!(backfill_until: chunk_end)
    end

    # Check if polling backfill has caught up to current time.
    # Uses 1-hour buffer to account for clock differences and processing time.
    def polling_backfill_complete?
      return false unless backfill_target && backfill_until
      backfill_until >= Time.current - 1.hour
    end

    # Progress percentage for polling backfill.
    def polling_backfill_progress_percent
      return 100 if polling_backfill_complete?
      return 0 unless backfill_target && backfill_until

      total = Time.current - backfill_target
      return 0 if total <= 0 # Guard against division by zero

      completed = backfill_until - backfill_target
      ((completed / total) * 100).round(1)
    end
  end
end
