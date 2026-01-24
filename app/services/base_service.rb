# frozen_string_literal: true

require "dry/monads"

class BaseService
  extend Dry::Initializer
  include Dry::Monads[:result]

  def self.call(...)
    new(...).call
  end

  def call
    raise NotImplementedError
  end
end
