# frozen_string_literal: true

require "dry/validation"

module NostrRelay
  module Contracts
    class EventContract < Dry::Validation::Contract
      HEX64 = /\A[a-f0-9]{64}\z/i
      HEX128 = /\A[a-f0-9]{128}\z/i

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

      rule(:created_at) do
        # Allow configurable grace period for clock skew (default 15 minutes)
        max_timestamp = Time.now.to_i + Config.created_at_grace_period
        key.failure("cannot be in future") if value > max_timestamp
      end

      rule(:kind) do
        # NIP-01: kind is "integer between 0 and 65535"
        key.failure("must be between 0 and 65535") unless value.between?(0, 65_535)
      end

      rule(:tags) do
        # Enforce max_event_tags limit from NIP-11
        max_tags = Config.max_event_tags
        key.failure("too many tags (max #{max_tags})") if value.size > max_tags

        # Validate each tag is an array of strings
        value.each_with_index do |tag, idx|
          unless tag.is_a?(Array) && tag.all? { |v| v.is_a?(String) }
            key.failure("tag[#{idx}] must be an array of strings")
            break
          end
        end
      end

      rule(:content) do
        # Enforce max_content_length limit from NIP-11
        max_len = Config.max_content_length
        key.failure("too large (max #{max_len} bytes)") if value.bytesize > max_len
      end
    end
  end
end
