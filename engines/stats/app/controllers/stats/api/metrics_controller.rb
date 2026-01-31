# frozen_string_literal: true

module Stats
  module Api
    class MetricsController < ActionController::API
      before_action :authenticate_api_key!, if: -> { Stats.authentication_enabled? }

      # GET /stats/api/metrics
      def index
        result = CollectOverview.call
        render_result(result)
      end

      # GET /stats/api/metrics/connections
      def connections
        result = CollectConnections.call
        render_result(result)
      end

      # GET /stats/api/metrics/events
      def events
        result = CollectEvents.call
        render_result(result)
      end

      # GET /stats/api/metrics/system
      def system
        result = CollectSystem.call
        render_result(result)
      end

      private

      def authenticate_api_key!
        token = extract_token
        return render_unauthorized unless token.present?

        api_key = ::ApiKey.authenticate(token)
        return render_unauthorized unless api_key

        @current_api_key = api_key
      end

      def extract_token
        # Support both Bearer token and query param
        auth_header = request.headers["Authorization"]
        if auth_header&.start_with?("Bearer ")
          auth_header.sub("Bearer ", "")
        else
          params[:token]
        end
      end

      def render_unauthorized
        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def render_result(result)
        if result.success?
          render json: result.value!
        else
          render json: { error: extract_error_message(result.failure) }, status: :internal_server_error
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
end
