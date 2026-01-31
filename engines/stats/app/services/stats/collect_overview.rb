# frozen_string_literal: true

module Stats
  class CollectOverview < ::BaseService
    include Dry::Monads[:result, :do]

    def call
      connections = yield CollectConnections.call
      events = yield CollectEvents.call
      system = yield CollectSystem.call

      Success(
        connections: connections,
        events: events,
        system: system,
        collected_at: Time.current.iso8601
      )
    rescue StandardError => e
      Rails.logger.error "[Stats] CollectOverview failed: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace&.first(10)&.join("\n")
      Failure(error: e.message)
    end
  end
end
