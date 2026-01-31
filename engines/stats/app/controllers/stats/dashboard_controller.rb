# frozen_string_literal: true

module Stats
  class DashboardController < ApplicationController
    skip_before_action :authenticate!, only: [ :login, :authenticate ], if: -> { Stats.authentication_enabled? }

    def index
      result = CollectOverview.call

      if result.success?
        @stats = result.value!
      else
        @stats = { error: extract_error_message(result.failure) || "Failed to collect stats" }
      end
    end

    def login
      render layout: false
    end

    def authenticate
      if params[:token].present?
        api_key = ::ApiKey.authenticate(params[:token])
        if api_key
          session[:stats_token] = params[:token]
          redirect_to root_path, notice: "Authenticated successfully"
        else
          redirect_to login_path, alert: "Invalid API key"
        end
      else
        redirect_to login_path, alert: "Token required"
      end
    end

    def logout
      session.delete(:stats_token)
      redirect_to login_path, notice: "Logged out"
    end
  end
end
