# frozen_string_literal: true

require "dry-types"

module RelaySync
  # Sync orchestration modes
  module SyncMode
    REALTIME = "realtime"
    BACKFILL = "backfill"
    FULL     = "full"
    UPLOAD   = "upload"

    ALL = [REALTIME, BACKFILL, FULL, UPLOAD].freeze
  end

  module Types
    include Dry.Types()

    RelayUrl = Strict::String.constrained(format: /\Awss?:\/\//)
    SubscriptionId = Strict::String.constrained(min_size: 1, max_size: 64)
    EventId = Strict::String.constrained(format: /\A[0-9a-f]{64}\z/i)
    ConnectionState = Strict::Symbol.enum(:disconnected, :connecting, :connected, :closing)
    SyncMode = Strict::String.enum(*RelaySync::SyncMode::ALL)
  end
end
