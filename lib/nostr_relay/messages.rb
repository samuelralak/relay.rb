# frozen_string_literal: true

module NostrRelay
  # NIP-01 message types and prefixes
  # https://github.com/nostr-protocol/nips/blob/master/01.md
  module Messages
    # Client → Relay message types
    module Inbound
      EVENT = "EVENT"
      REQ   = "REQ"
      CLOSE = "CLOSE"
      AUTH  = "AUTH"  # NIP-42

      ALL = [ EVENT, REQ, CLOSE, AUTH ].freeze
    end

    # Relay → Client message types
    module Outbound
      EVENT  = "EVENT"
      OK     = "OK"
      EOSE   = "EOSE"
      CLOSED = "CLOSED"
      NOTICE = "NOTICE"
      AUTH   = "AUTH"  # NIP-42

      ALL = [ EVENT, OK, EOSE, CLOSED, NOTICE, AUTH ].freeze
    end

    # OK/CLOSED message prefixes (NIP-01)
    # Format: "prefix: human-readable message"
    module Prefix
      DUPLICATE     = "duplicate:"
      INVALID       = "invalid:"
      BLOCKED       = "blocked:"
      RATE_LIMITED  = "rate-limited:"
      RESTRICTED    = "restricted:"
      POW           = "pow:"
      ERROR         = "error:"
      MUTE          = "mute:"
      AUTH_REQUIRED = "auth-required:"  # NIP-42

      # Build a prefixed message
      def self.build(prefix, message = "")
        message.empty? ? prefix : "#{prefix} #{message}"
      end
    end
  end
end
