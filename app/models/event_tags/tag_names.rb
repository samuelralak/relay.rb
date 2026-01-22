# frozen_string_literal: true

module EventTags
  # Standard tag names per NIPs
  # https://github.com/nostr-protocol/nips
  module TagNames
    # Core reference tags (NIP-01)
    EVENT = "e"           # Event reference
    PUBKEY = "p"          # Pubkey reference
    ADDRESSABLE = "a"     # Addressable event reference
    IDENTIFIER = "d"      # Identifier for addressable events

    # Content tags
    HASHTAG = "t"         # Hashtag (NIP-24)
    REFERENCE = "r"       # URL or relay reference (NIP-24, NIP-65)
    GEOHASH = "g"         # Geohash (NIP-52)
    KIND = "k"            # Kind reference (NIP-18, NIP-25)

    # Comment root tags (NIP-22)
    ROOT_EVENT = "E"      # Root event
    ROOT_ADDRESS = "A"    # Root address
    ROOT_IDENTITY = "I"   # Root external identity
    ROOT_PUBKEY = "P"     # Root pubkey
    ROOT_SCOPE = "K"      # Root scope

    # Labeling (NIP-32)
    LABEL = "l"           # Label
    LABEL_NAMESPACE = "L" # Label namespace

    # Media & content
    CONTENT_WARNING = "content-warning" # Sensitive content (NIP-36)
    SUBJECT = "subject"   # Subject line (NIP-14)
    TITLE = "title"       # Title (NIP-23)
    SUMMARY = "summary"   # Summary (NIP-23)
    IMAGE = "image"       # Image URL (NIP-23)
    IMETA = "imeta"       # Inline metadata (NIP-92)

    # Protocol
    EXPIRATION = "expiration" # Expiration timestamp (NIP-40)
    NONCE = "nonce"       # Proof of work (NIP-13)
    RELAY = "relay"       # Relay hint (NIP-42)
    CHALLENGE = "challenge" # Auth challenge (NIP-42)
    ALT = "alt"           # Alt text for unknown events (NIP-31)

    # Payment
    AMOUNT = "amount"     # Amount in millisats (NIP-57)
    BOLT11 = "bolt11"     # Lightning invoice (NIP-57)
    LNURL = "lnurl"       # LNURL (NIP-57)
    ZAP = "zap"           # Zap split (NIP-57)

    # Single-letter indexable tags (a-z, A-Z per NIP-01)
    # Using Set for O(1) lookup instead of Array#include? which is O(n)
    INDEXABLE = Set.new(("a".."z").to_a + ("A".."Z").to_a).freeze

    class << self
      def indexable?(tag_name)
        tag_name.is_a?(String) && tag_name.length == 1 && INDEXABLE.include?(tag_name)
      end
    end
  end
end
