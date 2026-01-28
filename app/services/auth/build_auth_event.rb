# frozen_string_literal: true

require "nostr"

module Auth
  # Builds a signed NIP-42 authentication event for outbound auth.
  # Used when our relay connects to upstream relays that require authentication.
  class BuildAuthEvent < BaseService
    include Dry::Monads[:result]

    option :challenge, type: Types::String
    option :relay_url, type: Types::String
    option :private_key, type: Types::String  # Hex-encoded 32-byte private key

    def call
      return Failure[:invalid, "challenge cannot be blank"] if challenge.blank?
      return Failure[:invalid, "relay_url cannot be blank"] if relay_url.blank?
      return Failure[:invalid, "private_key cannot be blank"] if private_key.blank?

      event = build_unsigned_event
      signed_event = sign_event(event)

      Success(event: signed_event)
    rescue StandardError => e
      Failure[:error, "failed to build auth event: #{e.message}"]
    end

    private

    def build_unsigned_event
      {
        "pubkey" => derive_pubkey,
        "created_at" => Time.now.to_i,
        "kind" => Events::Kinds::AUTH,
        "tags" => [
          [ "relay", relay_url ],
          [ "challenge", challenge ]
        ],
        "content" => ""
      }
    end

    def derive_pubkey
      keypair.public_key.to_s
    end

    def sign_event(event)
      # Compute event ID (SHA256 of canonical JSON)
      result = Actions::ComputeEventId.call(event:)
      event_id = result.value![:event_id]
      event["id"] = event_id

      # Sign with Schnorr using nostr gem
      signature = crypto.sign_message(event_id, keypair.private_key)
      event["sig"] = signature

      event
    end

    def keypair
      @keypair ||= Nostr::Keygen.new.get_key_pair_from_private_key(
        Nostr::PrivateKey.new(private_key)
      )
    end

    def crypto
      @crypto ||= Nostr::Crypto.new
    end
  end
end
