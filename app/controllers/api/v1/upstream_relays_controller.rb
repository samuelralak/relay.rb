# frozen_string_literal: true

module Api
  module V1
    class UpstreamRelaysController < BaseController
      before_action :set_relay, only: %i[show update destroy]

      def index
        relays = UpstreamRelay.all
        render json: relays
      end

      def show
        render json: @relay
      end

      def create
        relay = UpstreamRelay.new(relay_params)

        if relay.save
          render json: relay, status: :created
        else
          render_errors(relay.errors.full_messages)
        end
      end

      def update
        if @relay.update(relay_params)
          render json: @relay
        else
          render_errors(@relay.errors.full_messages)
        end
      end

      def destroy
        @relay.destroy
        head :no_content
      end

      private

      def set_relay
        @relay = UpstreamRelay.find(params[:id])
      end

      def relay_params
        params.require(:upstream_relay).permit(
          :url, :enabled, :backfill, :negentropy, :direction, :notes, config: {}
        )
      end
    end
  end
end
