# frozen_string_literal: true

module ApiKeyAuthenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_api_key
  end

  private

  def authenticate_api_key!
    token = extract_bearer_token
    @current_api_key = ApiKey.authenticate(token)

    unless @current_api_key
      render json: { error: "Invalid or missing API key" }, status: :unauthorized
      return
    end

    @current_api_key.touch_last_used!
  end

  def extract_bearer_token
    auth = request.headers["Authorization"]
    auth&.start_with?("Bearer ") ? auth.split(" ", 2).last : nil
  end
end
