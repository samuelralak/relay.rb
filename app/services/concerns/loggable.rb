# frozen_string_literal: true

module Loggable
  extend ActiveSupport::Concern

  private

  # @return [AppLogger::TaggedLogger]
  def logger
    @_logger ||= AppLogger[self.class.name]
  end
end
