# frozen_string_literal: true

module Stats
  class MetricsChannel < ActionCable::Channel::Base
    def subscribed
      # Reject if authentication is enabled but connection is not authenticated
      if Stats.authentication_enabled? && !authenticated?
        reject
        return
      end

      stream_from "stats:metrics"

      # Send initial data immediately
      transmit(collect_current_stats)
    end

    def unsubscribed
      # Cleanup if needed
    end

    private

    # Check if the connection has a valid session token
    # ActionCable connections share cookies with the main app
    def authenticated?
      return true unless Stats.authentication_enabled?

      # Check for session-based authentication (from dashboard login)
      token = connection.env["rack.session"]&.dig(:stats_token)
      return false unless token.present?

      ::ApiKey.authenticate(token).present?
    rescue StandardError
      false
    end

    def collect_current_stats
      result = CollectOverview.call
      if result.success?
        result.value!
      else
        { error: extract_error_message(result.failure) }
      end
    end

    def extract_error_message(failure)
      case failure
      when Hash then failure[:error] || "Unknown error"
      when String then failure
      else failure.to_s.presence || "Unknown error"
      end
    end
  end
end
