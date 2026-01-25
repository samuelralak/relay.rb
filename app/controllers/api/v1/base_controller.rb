# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      include ApiKeyAuthenticatable

      before_action :authenticate_api_key!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      private

      def render_not_found
        render json: { error: "Resource not found" }, status: :not_found
      end

      def render_error(message, status: :unprocessable_entity)
        render json: { error: message }, status:
      end

      def render_errors(errors, status: :unprocessable_entity)
        render json: { errors: }, status:
      end
    end
  end
end
