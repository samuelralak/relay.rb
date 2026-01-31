# frozen_string_literal: true

module Stats
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    before_action :authenticate!, if: -> { Stats.authentication_enabled? }

    layout "stats/application"

    helper_method :current_api_key

    private

    def authenticate!
      token = session[:stats_token] || params[:token]
      return redirect_to_login unless token.present?

      api_key = ::ApiKey.authenticate(token)
      if api_key
        session[:stats_token] = token
        @current_api_key = api_key
      else
        session.delete(:stats_token)
        redirect_to_login(alert: "Invalid or expired token")
      end
    end

    def current_api_key
      return nil unless Stats.authentication_enabled?
      @current_api_key
    end

    def redirect_to_login(alert: nil)
      flash[:alert] = alert if alert
      redirect_to login_path
    end

    # Extract error message from monad Failure result
    # Handles both Hash failures (with :error key) and other failure types
    def extract_error_message(failure)
      case failure
      when Hash
        failure[:error] || failure.to_s
      else
        failure.to_s
      end
    end
  end
end
