# frozen_string_literal: true

require "dry/monads"

class BaseService
  extend Dry::Initializer
  include ResultWrapper  # Provides Success() and Failure() with hash access
  include Dry::Monads::Do.for(:call)  # Enables yield syntax for chaining

  # Enable .call(...) class method that instantiates and calls
  def self.call(...)
    new(...).call
  end

  # Subclasses implement this
  def call
    raise NotImplementedError
  end
end
