# frozen_string_literal: true

# NIP-11: Relay Information Document
class RelayInfoController < ApplicationController
  def show
    render json: Rails.application.config.relay_info
  end
end
