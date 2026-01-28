# frozen_string_literal: true

module RelaySync
  # NIP-01 message types for relay sync client
  # https://github.com/nostr-protocol/nips/blob/master/01.md
  #
  # Note: RelaySync is a client, so directions are opposite of NostrRelay:
  # - Outbound = Client → Relay (we send)
  # - Inbound = Relay → Client (we receive)
  module Messages
    # Client → Relay message types (we send these)
    module Outbound
      EVENT = "EVENT"
      REQ   = "REQ"
      CLOSE = "CLOSE"

      ALL = [ EVENT, REQ, CLOSE ].freeze
    end

    # Relay → Client message types (we receive these)
    module Inbound
      EVENT  = "EVENT"
      OK     = "OK"
      EOSE   = "EOSE"
      CLOSED = "CLOSED"
      NOTICE = "NOTICE"
      AUTH   = "AUTH"

      ALL = [ EVENT, OK, EOSE, CLOSED, NOTICE, AUTH ].freeze
    end
  end
end
