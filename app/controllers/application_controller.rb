# frozen_string_literal: true

class ApplicationController < ActionController::API
  after_action :set_response_headers

  private

  def set_response_headers
    response.headers["Content-Type"] = "application/nostr+json"
    response.headers["Access-Control-Allow-Origin"] = "*"
  end
end
