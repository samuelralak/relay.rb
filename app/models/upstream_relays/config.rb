# frozen_string_literal: true

module UpstreamRelays
  class Config < Dry::Struct
    transform_keys(&:to_sym)

    # All commonly used Nostr event kinds (NIPs)
    # Regular events (0-9999), replaceable (10000-19999),
    # addressable (30000-39999)
    # Note: Ephemeral events (20000-29999) are excluded - not meant to be stored
    DEFAULT_EVENT_KINDS = [
      # Core events (NIP-01)
      0,      # Metadata
      1,      # Short text note
      2,      # Recommend relay (deprecated)
      3,      # Follows (NIP-02)
      4,      # Encrypted DM (NIP-04)
      5,      # Event deletion (NIP-09)
      6,      # Repost (NIP-18)
      7,      # Reaction (NIP-25)
      8,      # Badge award (NIP-58)

      # Privacy/DMs (NIP-17, NIP-59)
      13,     # Seal
      14,     # Direct Message
      16,     # Generic repost (NIP-18)
      1059,   # Gift Wrap

      # Channels (NIP-28)
      40,     # Channel creation
      41,     # Channel metadata
      42,     # Channel message
      43,     # Channel hide message
      44,     # Channel mute user

      # Regular events
      1063,   # File metadata (NIP-94)
      1111,   # Comment (NIP-22)
      1311,   # Live chat message (NIP-53)
      1984,   # Reporting (NIP-56)
      1985,   # Label (NIP-32)
      4550,   # Community post approval (NIP-72)
      9734,   # Zap request (NIP-57)
      9735,   # Zap (NIP-57)
      9802,   # Highlights (NIP-84)

      # Replaceable lists (NIP-51)
      10000,  # Mute list
      10001,  # Pin list
      10002,  # Relay list metadata (NIP-65)
      10003,  # Bookmarks list
      10004,  # Communities list
      10005,  # Public chats list
      10006,  # Blocked relays list
      10007,  # Search relays list
      10009,  # User groups list
      10015,  # Interests list
      10030,  # Emoji list

      # Addressable sets (NIP-51)
      30000,  # Follow sets
      30001,  # Generic lists
      30002,  # Relay sets
      30003,  # Bookmark sets
      30004,  # Curation sets
      30008,  # Profile badges (NIP-58)
      30009,  # Badge definition (NIP-58)
      30015,  # Interest sets
      30017,  # Stall (NIP-15)
      30018,  # Product (NIP-15)
      30023,  # Long-form content (NIP-23)
      30024,  # Draft long-form content (NIP-23)
      30030,  # Emoji sets (NIP-30)
      30078,  # Application-specific data (NIP-78)
      30311,  # Live event (NIP-53)
      30315,  # User statuses (NIP-38)

      # Wiki (NIP-54)
      30818,  # Wiki article
      30819,  # Wiki revision

      # Calendar (NIP-52)
      31922,  # Date-based calendar event
      31923,  # Time-based calendar event
      31924,  # Calendar
      31925,  # Calendar event RSVP

      # Handlers (NIP-89)
      31989,  # Handler recommendation
      31990,  # Handler information

      # Apollo
      31993,  # Apollo Question
      32017,  # Apollo Answer

      # Communities (NIP-72)
      34550   # Community definition
    ].freeze

    # Connection settings
    attribute :batch_size, Types::Coercible::Integer.default(100)
    attribute :max_concurrent_connections, Types::Coercible::Integer.default(10)
    attribute :reconnect_delay_seconds, Types::Coercible::Integer.default(5)
    attribute :max_reconnect_attempts, Types::Coercible::Integer.default(10)

    # Backfill settings
    attribute :backfill_since_hours, Types::Coercible::Integer.default(43_800) # 5 years
    attribute :event_kinds, Types::Array.of(Types::Coercible::Integer).default(DEFAULT_EVENT_KINDS)

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
