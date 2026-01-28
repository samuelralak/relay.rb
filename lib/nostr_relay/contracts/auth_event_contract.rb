# frozen_string_literal: true

require "dry/validation"

module NostrRelay
  module Contracts
    # Validates NIP-42 authentication event structure (kind 22242).
    # Auth events must have:
    # - Standard event fields (id, pubkey, created_at, kind, tags, content, sig)
    # - kind == 22242
    # - "relay" tag with the relay URL
    # - "challenge" tag with the challenge string
    # - Empty content
    class AuthEventContract < Dry::Validation::Contract
      include EventConstants

      params do
        required(:id).filled(:string)
        required(:pubkey).filled(:string)
        required(:created_at).filled(:integer)
        required(:kind).filled(:integer)
        required(:tags).value(:array)
        required(:content).value(:string)
        required(:sig).filled(:string)
      end

      rule(:id) do
        key.failure("must be 64 hex chars") unless value.match?(HEX64)
      end

      rule(:pubkey) do
        key.failure("must be 64 hex chars") unless value.match?(HEX64)
      end

      rule(:sig) do
        key.failure("must be 128 hex chars") unless value.match?(HEX128)
      end

      rule(:kind) do
        # NIP-42: Authentication events must be kind 22242
        key.failure("must be 22242 for authentication events") unless value == 22_242
      end

      rule(:tags) do
        # Validate each tag is an array of strings
        value.each_with_index do |tag, idx|
          unless tag.is_a?(Array) && tag.all? { |v| v.is_a?(String) }
            key.failure("tag[#{idx}] must be an array of strings")
            break
          end
        end

        # NIP-42: Must have "relay" tag
        relay_tag = value.find { |t| t.is_a?(Array) && t[0] == "relay" }
        key.failure("must contain a 'relay' tag") unless relay_tag
        key.failure("'relay' tag must have a value") if relay_tag && relay_tag.size < 2

        # NIP-42: Must have "challenge" tag
        challenge_tag = value.find { |t| t.is_a?(Array) && t[0] == "challenge" }
        key.failure("must contain a 'challenge' tag") unless challenge_tag
        key.failure("'challenge' tag must have a value") if challenge_tag && challenge_tag.size < 2
      end

      rule(:content) do
        # NIP-42: Content should be empty
        key.failure("should be empty for authentication events") unless value.empty?
      end
    end
  end
end
