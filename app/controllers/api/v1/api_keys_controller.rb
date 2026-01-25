# frozen_string_literal: true

module Api
  module V1
    class ApiKeysController < BaseController
      def index
        keys = ApiKey.active.select(:id, :name, :key_prefix, :created_at, :last_used_at)
        render json: keys
      end

      def create
        api_key = ApiKey.new(api_key_params)

        if api_key.save
          render json: {
            id: api_key.id,
            name: api_key.name,
            token: api_key.token,
            key_prefix: api_key.key_prefix,
            created_at: api_key.created_at,
            message: "Save this token - it will not be shown again"
          }, status: :created
        else
          render_errors(api_key.errors.full_messages)
        end
      end

      def destroy
        api_key = ApiKey.find(params[:id])
        api_key.revoke!
        head :no_content
      end

      private

      def api_key_params
        params.require(:api_key).permit(:name)
      end
    end
  end
end
