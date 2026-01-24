# frozen_string_literal: true

module Sync
  # Provides thread-safe waiting patterns with timeouts.
  # Include this in services that need to wait for async operations to complete.
  module TimeoutWaitable
    extend ActiveSupport::Concern

    # Thread-safe tracker for sync operation state
    class SyncTracker
      attr_reader :mutex, :condition

      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @complete = false
        @error = nil
      end

      # Thread-safe check for completion (use outside synchronized blocks)
      def complete?
        @mutex.synchronize { @complete }
      end

      # Non-locking check for use inside synchronized blocks only
      # Avoids deadlock when called from within wait_with_timeout
      def complete_unlocked?
        @complete
      end

      # Thread-safe error accessor (use outside synchronized blocks)
      def error
        @mutex.synchronize { @error }
      end

      # Non-locking error accessor for use inside synchronized blocks only
      def error_unlocked
        @error
      end

      def mark_complete!
        @mutex.synchronize do
          @complete = true
          @condition.broadcast
        end
      end

      # For use inside synchronize blocks only - avoids deadlock
      # Must be called while already holding the mutex
      def mark_complete_unlocked!
        @complete = true
        @condition.broadcast
      end

      def mark_error!(message)
        @mutex.synchronize do
          @error = message
          @complete = true  # Signal completion so waiting stops
          @condition.broadcast
        end
      end

      # Yields to block with mutex locked, useful for accumulating results
      def synchronize(&)
        @mutex.synchronize(&)
      end
    end

    private

    # Creates a new SyncTracker for managing async operation state
    def create_sync_tracker
      SyncTracker.new
    end

    # Waits for a condition to become true with a timeout.
    # @param timeout [Integer] Maximum seconds to wait
    # @param tracker [SyncTracker] The tracker to wait on
    # @param condition_check [Proc] Block that returns true when done (called inside mutex)
    # @return [Boolean] true if condition was met, false if timeout
    def wait_with_timeout(timeout:, tracker:, &condition_check)
      deadline = Time.now + timeout
      max_wait = Constants::Timeouts::CONDITION_WAIT

      tracker.mutex.synchronize do
        until condition_check.call
          remaining = deadline - Time.now
          return false if remaining <= 0

          # Wait in intervals to periodically check deadline
          wait_time = [ remaining, max_wait ].min
          tracker.condition.wait(tracker.mutex, wait_time)
        end
        true
      end
    end
  end
end
