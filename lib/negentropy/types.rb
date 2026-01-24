# frozen_string_literal: true

require "dry-types"

module Negentropy
  # NIP-77 Negentropy protocol message types
  module MessageType
    NEG_OPEN  = "NEG-OPEN"
    NEG_MSG   = "NEG-MSG"
    NEG_CLOSE = "NEG-CLOSE"
    NEG_ERR   = "NEG-ERR"

    ALL = [NEG_OPEN, NEG_MSG, NEG_CLOSE, NEG_ERR].freeze
  end

  module Types
    include Dry.Types()

    Timestamp = Strict::Integer.constrained(gteq: 0)
    IdBytes = Strict::String.constrained(size: 32)
    FingerprintBytes = Strict::String.constrained(size: 16)
    HexString = Strict::String.constrained(format: /\A[0-9a-f]*\z/i)
    MessageType = Strict::String.enum(*Negentropy::MessageType::ALL)
  end
end
