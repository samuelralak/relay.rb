# frozen_string_literal: true

require "dry-types"

module Types
  include Dry.Types()

  # Nostr types
  HexString = Strict::String.constrained(format: /\A[a-f0-9]+\z/i)
  EventId = HexString.constrained(size: 64)
  Pubkey = HexString.constrained(size: 64)

  # Sync types
  RelayUrl = Strict::String.constrained(format: /\Awss?:\/\//)
  Direction = Strict::String.enum("down", "up", "both")

  # Filter types
  FilterHash = Strict::Hash.schema(
    kinds?: Types::Array.of(Types::Integer),
    authors?: Types::Array.of(EventId),
    since?: Types::Integer,
    until?: Types::Integer
  ).with_key_transform(&:to_sym)
end
