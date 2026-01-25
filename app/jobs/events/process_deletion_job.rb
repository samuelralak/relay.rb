# frozen_string_literal: true

module Events
  # NIP-09: Enqueues deletion processing for background execution.
  class ProcessDeletionJob < ApplicationJob
    queue_as :deletions

    # @param deletion_event_id [String] UUID of the stored deletion event
    def perform(deletion_event_id)
      DeleteEvent.call(deletion_event_id:)
    end
  end
end
