# frozen_string_literal: true

class BaseService
  extend Dry::Initializer

  # Enable .call(...) class method that instantiates and calls
  def self.call(...)
    new(...).call
  end

  # Subclasses implement this
  def call
    raise NotImplementedError
  end
end
