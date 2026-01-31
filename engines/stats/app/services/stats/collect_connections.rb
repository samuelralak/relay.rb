# frozen_string_literal: true

module Stats
  class CollectConnections < ::BaseService
    def call
      registry = Stats.connection_registry

      Success(
        total: registry.connection_count,
        details: registry.connection_details,
        total_subscriptions: Stats.subscriptions.total_subscription_count
      )
    rescue StandardError => e
      Rails.logger.error "[Stats] CollectConnections failed: #{e.class} - #{e.message}"
      Failure(error: e.message)
    end
  end
end
