# frozen_string_literal: true

require "dry-types"

module Negentropy
  module Types
    include Dry.Types()

    Timestamp = Strict::Integer.constrained(gteq: 0)
    IdBytes = Strict::String.constrained(size: 32)
    FingerprintBytes = Strict::String.constrained(size: 16)
    HexString = Strict::String.constrained(format: /\A[0-9a-f]*\z/i)
  end
end
