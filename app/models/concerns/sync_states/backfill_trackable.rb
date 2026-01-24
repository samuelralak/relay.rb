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
  end
end
