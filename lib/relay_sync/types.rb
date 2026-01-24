# frozen_string_literal: true

require "dry-types"

module RelaySync
  module Types
    include Dry.Types()

    RelayUrl = Strict::String.constrained(format: /\Awss?:\/\//)
    SubscriptionId = Strict::String.constrained(min_size: 1, max_size: 64)
    EventId = Strict::String.constrained(format: /\A[0-9a-f]{64}\z/i)
    ConnectionState = Strict::Symbol.enum(:disconnected, :connecting, :connected, :closing)
  end
end
