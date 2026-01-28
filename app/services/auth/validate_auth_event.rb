# frozen_string_literal: true

require "digest"
require "nostr"

module Auth
  # Validates NIP-42 authentication events (kind 22242).
  # Verifies:
  # - Event structure and signature
  # - Kind is exactly 22242
  # - Timestamp is within acceptable range (±10 minutes)
  # - Challenge tag matches the connection's challenge
  # - Relay URL tag matches this relay's URL
  class ValidateAuthEvent < BaseService
    include Dry::Monads[:result, :do]

    option :event_data, type: Types::Hash
    option :connection_challenge, type: Types::String
    option :relay_url, type: Types::String

    # NIP-42 suggests ~10 minutes tolerance for timestamp
    AUTH_TIMEOUT_SECONDS = 600

    def call
      @data = event_data.transform_keys(&:to_s)

      yield validate_contract
      yield verify_kind
      yield verify_timestamp
      yield verify_challenge_tag
      yield verify_relay_url_tag
      yield verify_id_and_signature

      Success(pubkey: @data["pubkey"])
    end

    private

    def validate_contract
      validation = NostrRelay::Contracts::AuthEventContract.new.call(@data)
      return Failure[:invalid, "invalid: #{validation.errors.to_h}"] unless validation.success?

      Success()
    end

    def verify_kind
      return Success() if @data["kind"] == Events::Kinds::AUTH

      Failure[:invalid, "invalid: kind must be 22242"]
    end

    def verify_timestamp
      now = Time.now.to_i
      created_at = @data["created_at"]

      if created_at < now - AUTH_TIMEOUT_SECONDS
        return Failure[:invalid, "invalid: timestamp too old"]
      end

      if created_at > now + AUTH_TIMEOUT_SECONDS
        return Failure[:invalid, "invalid: timestamp too far in future"]
      end

      Success()
    end

    def verify_challenge_tag
      challenge_tag = find_tag("challenge")
      return Failure[:invalid, "invalid: missing challenge tag"] unless challenge_tag
      return Failure[:invalid, "invalid: challenge mismatch"] unless challenge_tag[1] == connection_challenge

      Success()
    end

    def verify_relay_url_tag
      relay_tag = find_tag("relay")
      return Failure[:invalid, "invalid: missing relay tag"] unless relay_tag

      expected_result = Actions::NormalizeRelayUrl.call(url: relay_url)
      actual_result = Actions::NormalizeRelayUrl.call(url: relay_tag[1])

      return Failure[:invalid, "invalid: relay URL invalid"] if expected_result.failure? || actual_result.failure?

      expected_normalized = expected_result.value![:normalized_url]
      actual_normalized = actual_result.value![:normalized_url]

      return Failure[:invalid, "invalid: relay URL mismatch"] unless expected_normalized == actual_normalized

      Success()
    end

    def verify_id_and_signature
      # Verify ID matches canonical JSON hash
      result = Actions::ComputeEventId.call(event: @data)
      computed_id = result.value![:event_id]
      return Failure[:invalid, "invalid: event id does not match"] unless computed_id == @data["id"]

      # Verify Schnorr signature (BIP-340)
      return Failure[:invalid, "invalid: bad signature"] unless signature_valid?

      Success()
    end

    def find_tag(name)
      (@data["tags"] || []).find { |t| t.is_a?(Array) && t[0] == name }
    end

    def signature_valid?
      crypto = Nostr::Crypto.new
      crypto.valid_sig?(
        @data["id"],
        Nostr::PublicKey.new(@data["pubkey"]),
        Nostr::Signature.new(@data["sig"])
      )
    rescue StandardError
      false
    end
  end
end
