# frozen_string_literal: true

module UpstreamRelays
  module Directions
    DOWN = "down"
    UP = "up"
    BOTH = "both"

    ALL = [ DOWN, UP, BOTH ].freeze

    DOWNLOAD_CAPABLE = [ DOWN, BOTH ].freeze
    UPLOAD_CAPABLE = [ UP, BOTH ].freeze
  end
end
