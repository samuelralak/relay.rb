# frozen_string_literal: true

module UpstreamRelays
  class Config < Dry::Struct
    transform_keys(&:to_sym)

    # Connection settings
    attribute :batch_size, Types::Coercible::Integer.default(100)
    attribute :max_concurrent_connections, Types::Coercible::Integer.default(10)
    attribute :reconnect_delay_seconds, Types::Coercible::Integer.default(5)
    attribute :max_reconnect_attempts, Types::Coercible::Integer.default(10)

    # Backfill settings
    attribute :backfill_since_hours, Types::Coercible::Integer.default(43_800) # 5 years
    attribute :event_kinds, Types::Array.of(Types::Coercible::Integer).default([ 0, 1, 3, 5, 6, 7, 30_023 ].freeze)

    # Negentropy settings
    attribute :negentropy_frame_size, Types::Coercible::Integer.default(60_000)
    attribute :negentropy_chunk_hours, Types::Coercible::Integer.default(2)

    # Polling settings
    attribute :polling_chunk_hours, Types::Coercible::Integer.default(6)
    attribute :polling_window_minutes, Types::Coercible::Integer.default(15)
    attribute :polling_timeout_seconds, Types::Coercible::Integer.default(30)

    # Upload settings
    attribute :upload_batch_size, Types::Coercible::Integer.default(50)
    attribute :upload_delay_ms, Types::Coercible::Integer.default(100)

    # Robustness settings
    attribute :resume_overlap_seconds, Types::Coercible::Integer.default(300)
    attribute :checkpoint_interval, Types::Coercible::Integer.default(100)
    attribute :stale_threshold_minutes, Types::Coercible::Integer.default(10)
    attribute :error_retry_after_minutes, Types::Coercible::Integer.default(30)

    # Convenience methods
    def backfill_since = backfill_since_hours * 3600
    def upload_delay = upload_delay_ms / 1000.0
    def reconnect_delay = reconnect_delay_seconds
  end
end
