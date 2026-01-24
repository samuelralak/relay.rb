# frozen_string_literal: true

require "dry/monads"

# Provides backward-compatible Result types that support hash-like access.
# Allows gradual migration from `result[:key]` to `result.value![:key]`.
module ResultWrapper
  include Dry::Monads[:result]

  # Success that supports hash-like access for backward compatibility
  class WrappedSuccess < Dry::Monads::Result::Success
    def [](key)
      val = value!
      return val[key] if val.is_a?(Hash)

      nil
    end

    def key?(key)
      val = value!
      val.is_a?(Hash) && val.key?(key)
    end
  end

  # Failure that supports hash-like access for backward compatibility
  class WrappedFailure < Dry::Monads::Result::Failure
    def [](key)
      case key
      when :success then false
      when :error then failure
      end
    end

    def key?(key)
      %i[success error].include?(key)
    end
  end

  def Success(value = nil)
    WrappedSuccess.new(value)
  end

  def Failure(error)
    WrappedFailure.new(error)
  end
end
