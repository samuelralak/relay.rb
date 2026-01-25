# frozen_string_literal: true

module Search
  class IndexEventJob < ApplicationJob
    queue_as :search

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    # Note: Uses database primary key (id), not Nostr event_id
    def perform(id:)
      event = Event.find(id)
      IndexEvent.call(event:)
    end
  end
end
