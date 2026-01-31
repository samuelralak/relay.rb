# frozen_string_literal: true

module Stats
  # Broadcasts stats metrics to all connected dashboard clients via ActionCable.
  # Scheduled by Solid Queue recurring jobs (config/recurring.yml) every 5 seconds.
  class BroadcastMetricsJob < ApplicationJob
    queue_as :default

    def perform
      result = CollectOverview.call

      if result.success?
        ActionCable.server.broadcast("stats:metrics", result.value!)
      else
        Rails.logger.warn "[Stats] Failed to collect metrics: #{result.failure}"
      end
    end
  end
end
